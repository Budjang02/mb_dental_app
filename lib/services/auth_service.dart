import 'package:supabase_flutter/supabase_flutter.dart';

import 'network_service.dart';
import 'session_controller.dart';
import 'supabase_service.dart';

/// The outcome of an auth call, so screens can show a message without having
/// to catch [AuthException] themselves.
class AuthResult {
  final bool success;
  final String? message;
  final User? user;
  final bool isRetryable;

  /// The session the call opened, or null when it opened none. Sign-up returns
  /// null here whenever the Supabase project has email confirmation switched
  /// on: the account exists, but nobody is signed in until the patient opens
  /// the emailed link.
  final Session? session;

  /// True when sign-in was refused only because the address has not been
  /// confirmed yet. The caller can send a fresh signup code and finish
  /// verification instead of leaving the patient stuck at Login.
  final bool emailNotConfirmed;

  const AuthResult._(
    this.success, {
    this.message,
    this.user,
    this.session,
    this.isRetryable = false,
    this.emailNotConfirmed = false,
  });

  const AuthResult.ok({User? user, Session? session})
      : this._(true, user: user, session: session);

  const AuthResult.failure(String message, {bool isRetryable = false})
      : this._(false, message: message, isRetryable: isRetryable);

  const AuthResult.unconfirmedEmail(String message)
      : this._(false, message: message, emailNotConfirmed: true);

  const AuthResult.networkFailure()
      : this._(
          false,
          message: kServerConnectionMessage,
          isRetryable: true,
        );

  /// True when the account was created but still has to be confirmed by email
  /// before it can be signed in to.
  bool get needsEmailConfirmation => success && user != null && session == null;
}

/// Email/password authentication against Supabase Auth.
///
/// Sessions are persisted by `supabase_flutter`, but a stored session is not
/// proof of a live one: `AuthGate` calls [SupabaseService.restoreSession] at
/// launch and only skips Login when that refresh succeeds.
class AuthService {
  AuthService._();

  /// Where Supabase sends the patient back after they open an auth email.
  /// Must match an entry under Authentication > URL Configuration > Redirect
  /// URLs in the Supabase dashboard, and the scheme registered in
  /// AndroidManifest.xml and ios/Runner/Info.plist.
  static const String _authRedirect = 'mbdental://login-callback';

  static Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await SupabaseService.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (response.user == null) {
        return const AuthResult.failure('Sign in failed. Please try again.');
      }
      return AuthResult.ok(user: response.user, session: response.session);
    } on AuthException catch (e) {
      if (_isEmailNotConfirmed(e)) return AuthResult.unconfirmedEmail(_friendly(e));
      return AuthResult.failure(
        _friendly(e),
        isRetryable: NetworkService.isConnectionFailure(e),
      );
    } catch (e) {
      return NetworkService.isConnectionFailure(e)
          ? const AuthResult.networkFailure()
          : const AuthResult.failure('Sign in failed. Please try again.');
    }
  }

  /// Creates the auth user. [fullName] and [phone] go into user metadata, which
  /// is where a database trigger can pick them up when it creates the matching
  /// patient row.
  static Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    try {
      // No pre-check for an existing address here. Until the code is
      // verified, sign-up only leaves a pending auth.users row (no profile,
      // no patient row), and GoTrue answers a repeat sign-up for that address
      // by sending a new code. A patient who backed out of the code screen
      // can therefore simply register again. A confirmed address is caught
      // below by its empty identities list.
      final response = await SupabaseService.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': fullName.trim(),
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
        emailRedirectTo: _authRedirect,
      );
      if (response.user == null) {
        return const AuthResult.failure('Sign up failed. Please try again.');
      }
      // An address that is already confirmed comes back as a user with no
      // identities rather than an error, so sign-up cannot be used to find out
      // who has an account. No code is sent in that case, so stop here instead
      // of opening a verification screen that would wait forever.
      final identities = response.user!.identities;
      if (identities != null && identities.isEmpty) {
        return const AuthResult.failure(
          'An account with this email address already exists. Please sign in instead.',
        );
      }
      // A session here means email confirmation is switched off in Supabase,
      // so no code was sent and the account would be usable unverified. Like
      // the website, drop the session and stop rather than finish sign-up.
      if (response.session != null) {
        await SupabaseService.auth.signOut(scope: SignOutScope.local);
        return const AuthResult.failure(
          'Email verification is required, but it is not switched on for this '
          'clinic yet. Please contact the clinic.',
        );
      }
      // A null session here is not a failure: it is the project telling us the
      // address has to be confirmed first. [AuthResult.needsEmailConfirmation]
      // is how the sign-up screen tells the two apart.
      return AuthResult.ok(user: response.user, session: response.session);
    } on AuthException catch (e) {
      return AuthResult.failure(
        _friendly(e),
        isRetryable: NetworkService.isConnectionFailure(e),
      );
    } catch (e) {
      return NetworkService.isConnectionFailure(e)
          ? const AuthResult.networkFailure()
          : const AuthResult.failure('We could not create your account. Please try again.');
    }
  }

  /// Confirms the address with the 6-digit code from the Confirm signup email.
  /// This is the same `verifyOtp` type 'signup' check the website runs, so a
  /// success confirms the account and opens its session; the
  /// on_auth_user_email_confirmed trigger then creates the patient row.
  static Future<AuthResult> verifySignupCode({
    required String email,
    required String code,
  }) async {
    try {
      final response = await SupabaseService.auth.verifyOTP(
        email: email.trim(),
        token: code.trim(),
        type: OtpType.signup,
      );
      if (response.session == null) {
        return const AuthResult.failure(_invalidCodeMessage);
      }
      return AuthResult.ok(user: response.user, session: response.session);
    } on AuthException catch (e) {
      if (NetworkService.isConnectionFailure(e)) return const AuthResult.networkFailure();
      if (_isRateLimited(e)) return AuthResult.failure(_friendly(e));
      return const AuthResult.failure(_invalidCodeMessage);
    } catch (e) {
      return NetworkService.isConnectionFailure(e)
          ? const AuthResult.networkFailure()
          : const AuthResult.failure('We could not verify the code. Please try again.');
    }
  }

  /// Emails a new signup code to [email]. Supabase replaces the previous code
  /// and enforces its own per-address cooldown, which comes back as an error
  /// here rather than a silent no-op.
  static Future<AuthResult> resendSignupCode(String email) async {
    try {
      await SupabaseService.auth.resend(
        email: email.trim(),
        type: OtpType.signup,
        emailRedirectTo: _authRedirect,
      );
      return const AuthResult.ok();
    } on AuthException catch (e) {
      return AuthResult.failure(
        _friendly(e),
        isRetryable: NetworkService.isConnectionFailure(e),
      );
    } catch (e) {
      return NetworkService.isConnectionFailure(e)
          ? const AuthResult.networkFailure()
          : const AuthResult.failure('We could not send a new code. Please try again.');
    }
  }

  static const String _invalidCodeMessage =
      'That code is invalid or has expired. Request a new one.';

  static bool _isEmailNotConfirmed(AuthException e) =>
      e.code == 'email_not_confirmed' ||
      e.message.toLowerCase().contains('email not confirmed');

  static bool _isRateLimited(AuthException e) {
    final message = e.message.toLowerCase();
    return e.statusCode == '429' ||
        message.contains('rate limit') ||
        message.contains('too many') ||
        message.contains('for security purposes');
  }

  /// Sends the password-reset email. Supabase does not reveal whether an
  /// address is registered, so the caller should show the same confirmation
  /// either way rather than leaking which emails exist.
  static Future<AuthResult> sendPasswordReset(String email) async {
    try {
      await SupabaseService.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: _authRedirect,
      );
      return const AuthResult.ok();
    } on AuthException catch (e) {
      return AuthResult.failure(
        _friendly(e),
        isRetryable: NetworkService.isConnectionFailure(e),
      );
    } catch (e) {
      return NetworkService.isConnectionFailure(e)
          ? const AuthResult.networkFailure()
          : const AuthResult.failure('We could not send the reset email. Please try again.');
    }
  }

  /// Sets a new password for the currently signed-in user. Used both by the
  /// reset-link flow and by Profile → Change Password.
  static Future<AuthResult> updatePassword(String newPassword) async {
    try {
      await SupabaseService.auth.updateUser(UserAttributes(password: newPassword));
      return const AuthResult.ok();
    } on AuthException catch (e) {
      return AuthResult.failure(
        _friendly(e),
        isRetryable: NetworkService.isConnectionFailure(e),
      );
    } catch (e) {
      return NetworkService.isConnectionFailure(e)
          ? const AuthResult.networkFailure()
          : const AuthResult.failure('We could not update your password. Please try again.');
    }
  }

  /// Profile → Change Password. Supabase's update call does not check the old
  /// password, so this re-authenticates with it first — otherwise anyone who
  /// picked up an unlocked phone could change the password without knowing it.
  static Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = SupabaseService.auth.currentUser?.email;
    if (email == null) {
      return const AuthResult.failure('You are signed out. Please sign in again.');
    }

    final reauth = await signIn(email: email, password: currentPassword);
    if (!reauth.success) {
      return const AuthResult.failure('Your current password is not correct.');
    }
    return updatePassword(newPassword);
  }

  /// Kept for callers that only want the auth half of a sign-out. Anything
  /// with a [BuildContext] should use `SessionController.logout` instead, which
  /// also clears the cached record and resets the navigator.
  static Future<void> signOut() => SessionController.signOut();

  /// Supabase's raw messages are aimed at developers; these are the ones a
  /// patient should actually read.
  static String _friendly(AuthException e) {
    if (NetworkService.isConnectionFailure(e)) return kServerConnectionMessage;
    final message = e.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'That email and password do not match an account.';
    }
    if (message.contains('for security purposes')) {
      // Supabase's resend cooldown: "you can only request this after N seconds".
      return 'Please wait a moment before requesting another code.';
    }
    if (_isEmailNotConfirmed(e)) {
      return 'Please confirm your email address first, then sign in.';
    }
    if (message.contains('already registered') || message.contains('already been registered')) {
      return 'An account with that email already exists. Try signing in instead.';
    }
    if (message.contains('password should be')) {
      return 'Password is too short. Use at least 6 characters.';
    }
    if (message.contains('rate limit') || message.contains('too many')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return 'We could not complete that request. Please try again.';
  }
}
