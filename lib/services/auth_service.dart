import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// The outcome of an auth call, so screens can show a message without having
/// to catch [AuthException] themselves.
class AuthResult {
  final bool success;
  final String? message;
  final User? user;

  const AuthResult._(this.success, {this.message, this.user});

  const AuthResult.ok({User? user}) : this._(true, user: user);

  const AuthResult.failure(String message) : this._(false, message: message);
}

/// Email/password authentication against Supabase Auth.
///
/// Sessions are persisted and refreshed by `supabase_flutter` itself, so a
/// patient who signed in once stays signed in until they sign out — the splash
/// screen reads [SupabaseService.isSignedIn] to skip straight to the dashboard.
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
      return AuthResult.ok(user: response.user);
    } on AuthException catch (e) {
      return AuthResult.failure(_friendly(e));
    } catch (_) {
      return const AuthResult.failure(
        'Could not reach the clinic server. Check your connection and try again.',
      );
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
      return AuthResult.ok(user: response.user);
    } on AuthException catch (e) {
      return AuthResult.failure(_friendly(e));
    } catch (_) {
      return const AuthResult.failure(
        'Could not reach the clinic server. Check your connection and try again.',
      );
    }
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
      return AuthResult.failure(_friendly(e));
    } catch (_) {
      return const AuthResult.failure(
        'Could not reach the clinic server. Check your connection and try again.',
      );
    }
  }

  /// Sets a new password for the currently signed-in user. Used both by the
  /// reset-link flow and by Profile → Change Password.
  static Future<AuthResult> updatePassword(String newPassword) async {
    try {
      await SupabaseService.auth.updateUser(UserAttributes(password: newPassword));
      return const AuthResult.ok();
    } on AuthException catch (e) {
      return AuthResult.failure(_friendly(e));
    } catch (_) {
      return const AuthResult.failure(
        'Could not reach the clinic server. Check your connection and try again.',
      );
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

  static Future<void> signOut() => SupabaseService.auth.signOut();

  /// Supabase's raw messages are aimed at developers; these are the ones a
  /// patient should actually read.
  static String _friendly(AuthException e) {
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
    return e.message;
  }
}
