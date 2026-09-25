import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/auth/login_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../services/supabase_service.dart';

/// The app's root widget, and the only place that decides between Login and
/// the dashboard.
///
/// It watches `onAuthStateChange` rather than reading the session once, so the
/// screen follows the session for as long as the app runs: a sign-out, a
/// revoked refresh token, or an expiry that cannot be refreshed swaps the
/// dashboard for [LoginScreen] on the spot. Neither screen is pushed as a
/// route, so there is never a protected screen left underneath Login.
///
/// The default is Login. The dashboard is shown only for a session that is
/// present and unexpired; everything else — no session, an expired one, a
/// stream error — falls through to credentials.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthState> _authStates =
      Supabase.instance.client.auth.onAuthStateChange;

  /// `Supabase.initialize()` restores the stored session from disk without
  /// proving it is still good, so the gate refreshes it before trusting it.
  /// Until this settles the app shows the loading state rather than guessing.
  SessionRestoreResult _sessionResult =
      SessionRestoreResult.temporarilyUnavailable;
  bool _sessionCheckDone = false;
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    // A refresh that succeeds emits `tokenRefreshed` and one that fails emits
    // `signedOut`, but a session that was already valid emits neither — so the
    // gate rebuilds on completion rather than waiting for an event.
    _checkRestoredSession();
  }

  Future<void> _checkRestoredSession() async {
    setState(() => _sessionCheckDone = false);
    final result = await SupabaseService.restoreSession();
    if (!mounted) return;
    setState(() {
      _sessionResult = result;
      _sessionCheckDone = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // The splash plays over the session check, so the refresh round trip costs
    // no extra time on screen.
    if (!_splashDone) {
      return SplashScreen(onFinished: () => setState(() => _splashDone = true));
    }

    return StreamBuilder<AuthState>(
      stream: _authStates,
      builder: (context, snapshot) {
        if (!_sessionCheckDone) {
          return const _GateLoading();
        }

        // The event carries the session it was raised for; `currentSession`
        // covers the first build, before the stream has emitted anything.
        final Session? session =
            SupabaseService.currentSession ?? snapshot.data?.session;

        if (session != null && !session.isExpired) {
          return const DashboardScreen();
        }
        if (_sessionResult == SessionRestoreResult.temporarilyUnavailable) {
          return _SessionRetry(onRetry: _checkRestoredSession);
        }
        return const LoginScreen();
      },
    );
  }
}

/// Shown only while the stored session is being checked at launch.
class _GateLoading extends StatelessWidget {
  const _GateLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Shown when Supabase could not refresh an expired access token because the
/// device is offline or the server is temporarily unavailable. It deliberately
/// does not expose protected data, but it also does not erase the refresh token.
class _SessionRetry extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _SessionRetry({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 16),
              const Text(
                'We could not restore your session.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Check your internet connection and try again.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
