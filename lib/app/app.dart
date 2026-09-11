import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme.dart';
import 'theme_controller.dart';
import 'routes.dart';
import '../screens/auth/create_new_password_screen.dart';
import '../repositories/clinic_api.dart';
import '../repositories/patient_repository.dart';
import '../screens/splash/splash_screen.dart';
import '../services/supabase_service.dart';
import '../widgets/push_banner.dart';

class DentalApp extends StatefulWidget {
  const DentalApp({super.key});

  @override
  State<DentalApp> createState() => _DentalAppState();
}

class _DentalAppState extends State<DentalApp> {
  /// Lets the auth listener navigate from outside the widget tree, which is
  /// where password-recovery links and expired sessions arrive.
  static final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = SupabaseService.onAuthStateChange.listen(_onAuthStateChange);

    // Supabase restores a stored session inside `Supabase.initialize()`, which
    // `main` awaits before `runApp`. Both the events that carry that restore
    // (`initialSession`, and the `signedIn` that `setInitialSession` raises)
    // have therefore already fired by the time the subscription above exists,
    // so a returning patient would otherwise never trigger a load and would
    // sit on a spinner forever. Kick it off here instead.
    if (SupabaseService.isSignedIn) _loadForSignedInPatient();
  }

  void _loadForSignedInPatient() {
    PatientRepository().load(force: true);
    ClinicCatalog().load(force: true);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _onAuthStateChange(AuthState state) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    switch (state.event) {
      // The patient opened the emailed reset link and it handed the app a
      // short-lived recovery session. That session is the proof of ownership,
      // so this is the only point where setting a new password is allowed.
      case AuthChangeEvent.passwordRecovery:
        navigator.push(
          MaterialPageRoute(
            builder: (_) => CreateNewPasswordScreen(
              email: SupabaseService.auth.currentUser?.email ?? '',
            ),
          ),
        );
      // Covers a deliberate sign-out and a refresh token the server rejected,
      // so a revoked session cannot leave patient data on screen.
      case AuthChangeEvent.signedOut:
        PatientRepository().clear();
        navigator.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
      // Fires on sign-in and on the session restored at launch, so the record
      // is fetched once per session from whichever route the patient entered by.
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.initialSession:
        if (SupabaseService.isSignedIn) _loadForSignedInPatient();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) {
        return MaterialApp(
          title: 'Mariano & Bolasoc Dental',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeController().mode,
          // Hosts the real-time alert banner above every route, so a push
          // arriving mid-flow is visible wherever the patient happens to be.
          builder: (context, child) => PushBannerHost(child: child ?? const SizedBox.shrink()),
          home: const SplashScreen(),
          routes: AppRoutes.routes,
        );
      },
    );
  }
}
