import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'network_service.dart';

/// The result of checking the session restored from device storage.
///
/// An expired access token is expected after the app has been backgrounded.
/// It is only a real sign-out when Supabase rejects the accompanying refresh
/// token. A network failure leaves the refresh token on the device so it can
/// be retried once connectivity returns.
enum SessionRestoreResult { active, signedOut, temporarilyUnavailable }

/// Single entry point for the Supabase backend.
///
/// Credentials come from the bundled `.env` (see `.env.example`), which holds
/// the anon/publishable key only. Every table this app touches is protected by
/// row-level security, so the key on its own grants nothing beyond the public
/// reference data (clinic details and the procedure catalog) — patient rows
/// only become visible once a patient signs in.
class SupabaseService {
  SupabaseService._();

  /// Reads `.env` and opens the connection. Must finish before `runApp`,
  /// because [client] and the auth screens assume an initialized instance.
  static Future<void> initialize() async {
    await dotenv.load(fileName: '.env');

    final url = dotenv.env['VITE_SUPABASE_URL']?.trim();
    final anonKey = dotenv.env['VITE_SUPABASE_ANON_KEY']?.trim();

    if (url == null || url.isEmpty || anonKey == null || anonKey.isEmpty) {
      throw StateError('Supabase configuration is missing.');
    }

    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw StateError('Supabase configuration is invalid.');
    }

    NetworkService.configure(uri);
    await Supabase.initialize(
      url: uri.toString(),
      publishableKey: anonKey,
      httpClient: ConnectivityAwareClient(),
    );
  }

  /// A reachability check for flows that should not wait for a network request
  /// to fail, such as the login button. It checks only the configured host.
  static Future<bool> canReachServer({bool force = false}) =>
      NetworkService.canReachServer(force: force);

  static SupabaseClient get client => Supabase.instance.client;

  static GoTrueClient get auth => client.auth;

  /// The signed-in patient's auth id, or null when nobody is signed in.
  /// This is the value RLS policies compare against, so it is also the key
  /// every patient-scoped query filters on.
  static String? get currentUserId => auth.currentUser?.id;

  /// The restored or freshly opened session, or null when nobody is signed in.
  ///
  /// This — not [User] — is what the app reads to decide whether it is signed
  /// in: a user object with no live session cannot satisfy a single RLS query.
  static Session? get currentSession => auth.currentSession;

  static bool get isSignedIn => auth.currentSession != null;

  /// True only for a session that is both present and still inside its access
  /// token's lifetime. A stored session that has run out is not a login.
  static bool get hasValidSession {
    final session = auth.currentSession;
    return session != null && !session.isExpired;
  }

  /// Resolves the stored session at launch, before any protected route is
  /// shown. Returns true only when a usable session survives the check.
  ///
  /// `Supabase.initialize()` restores whatever was in local storage without
  /// proving it is still good, so an expired or server-revoked session would
  /// otherwise be enough to walk straight past Login. Refreshing it here is
  /// what tells the two apart, and a refresh the server refuses ends the
  /// session locally rather than leaving a dead one on disk.
  static Future<SessionRestoreResult> restoreSession() async {
    final session = auth.currentSession;
    if (session == null) return SessionRestoreResult.signedOut;
    if (!session.isExpired) return SessionRestoreResult.active;

    try {
      final refreshed = await auth.refreshSession();
      return refreshed.session != null && !refreshed.session!.isExpired
          ? SessionRestoreResult.active
          : SessionRestoreResult.signedOut;
    } on AuthRetryableFetchException {
      // Offline, a timeout, or a 5xx response is not evidence that the
      // refresh token is invalid. GoTrue retains the session in this case.
      return SessionRestoreResult.temporarilyUnavailable;
    } on AuthException {
      // A non-retryable auth error means the refresh token is missing, revoked,
      // or otherwise unusable. GoTrue normally clears it itself; this covers a
      // malformed locally stored session that could not reach that path.
      try {
        if (auth.currentSession != null) {
          await auth.signOut(scope: SignOutScope.local);
        }
      } catch (_) {
        // Already signed out, or storage is unavailable; nothing else to do.
      }
      return SessionRestoreResult.signedOut;
    } catch (_) {
      // Do not discard a session for an unexpected local failure. The user can
      // retry this check after the app regains a working connection.
      return SessionRestoreResult.temporarilyUnavailable;
    }
  }

  /// Emits on sign-in, sign-out, and token refresh. The root widget listens to
  /// send a revoked or expired session back to Login.
  static Stream<AuthState> get onAuthStateChange => auth.onAuthStateChange;
}
