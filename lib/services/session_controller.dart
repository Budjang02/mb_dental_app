import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/auth_gate.dart';
import '../repositories/patient_repository.dart';
import 'realtime_sync_service.dart';
import 'supabase_service.dart';

/// Owns the end of a session: signing out of Supabase, dropping everything the
/// previous account left on the device, and putting the patient back on Login
/// with no protected route left behind them.
///
/// Screens call [logout] rather than [SupabaseService.auth.signOut] directly,
/// so a sign-out is the same three steps wherever it is triggered from.
class SessionController {
  SessionController._();

  /// Local keys written while signed in. They are not auth tokens, but they
  /// describe the previous patient's state, so they go when the session does.
  static const List<String> _sessionScopedPrefsKeys = <String>[
    'wallet_pending_topup',
  ];

  /// Signs out, clears local state, and resets the navigator to the gate,
  /// which shows Login because the session is gone.
  ///
  /// Never throws: a sign-out that cannot reach the server still has to end
  /// the session on this device, otherwise the patient stays on the dashboard
  /// with a session they have already asked to end.
  ///
  /// The route pushed is [AuthGate] rather than [LoginScreen] itself. Pushing
  /// Login directly would put a second copy above the gate, outside the auth
  /// stream's reach, and signing in from that copy would leave the patient on
  /// a login screen with an open session behind it.
  static Future<void> logout(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    await signOut();
    if (!context.mounted) return;
    // Wipes the backstack, so the system back button cannot return to the
    // dashboard after signing out.
    await navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  /// The non-navigating half of [logout]. Also used by the auth listener, which
  /// reacts to a sign-out that the server — not the patient — initiated.
  static Future<void> signOut() async {
    try {
      await SupabaseService.auth.signOut();
    } on AuthException {
      // The server rejected the token (already revoked, or expired). The local
      // session is cleared either way, which is what matters here.
    } catch (_) {
      // Offline. Same reasoning: the device-side sign-out has already happened.
    } finally {
      await clearLocalState();
    }
  }

  /// Drops every cached trace of the account: the in-memory record, the
  /// realtime subscriptions opened for it, and the session-scoped preferences.
  static Future<void> clearLocalState() async {
    PatientRepository().clear();
    await RealtimeSyncService().stop();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _sessionScopedPrefsKeys) {
        await prefs.remove(key);
      }
    } catch (_) {
      // Preferences are a cache; failing to clear one must not block sign-out.
    }
  }
}
