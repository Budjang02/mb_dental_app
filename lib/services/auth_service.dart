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

  const AuthResult._(
    this.success, {
    this.message,
    this.user,
    this.session,
    this.isRetryable = false,
  });

  const AuthResult.ok({User? user, Session? session})
      : this._(true, user: user, session: session);

  const AuthResult.failure(String message, {bool isRetryable = false})
      : this._(false, message: message, isRetryable: isRetryable);

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

  static Future<AuthResult?> _networkFailureIfOffline() async {
    return await SupabaseService.canReachServer() ? null : const AuthResult.networkFailure();
  }

  static Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    final networkFailure = await _networkFailureIfOffline();
    if (networkFailure != null) return networkFailure;
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
    final networkFailure = await _networkFailureIfOffline();
    if (networkFailure != null) return networkFailure;
    try {
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

  /// Sends the password-reset email. Supabase does not reveal whether an
  /// address is registered, so the caller should show the same confirmation
  /// either way rather than leaking which emails exist.
  static Future<AuthResult> sendPasswordReset(String email) async {
    final networkFailure = await _networkFailureIfOffline();
    if (networkFailure != null) return networkFailure;
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
    final networkFailure = await _networkFailureIfOffline();
    if (networkFailure != null) return networkFailure;
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
    if (message.contains('email not confirmed')) {
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
