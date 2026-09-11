import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:lottie/lottie.dart';
import '../../app/routes.dart';
import '../../services/supabase_service.dart';
import '../auth/login_screen.dart';

/// Full-bleed animated splash. The Lottie composition is decoded before this
/// widget paints anything (see [initState]), and the native OS splash is
/// kept pinned until that decode finishes — so the very first thing drawn is
/// an animation frame, never a bare plain-color screen. It then plays once
/// through before handing off to Login, or straight to the dashboard when a
/// stored session is still valid.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _assetPath = 'assets/animations/logo_splash.json';

  /// The teal the animation paints its own background rect with. Used behind
  /// the animation so there is never a visible seam at the screen edges.
  static const _backdrop = Color(0xFF119589);

  double _opacity = 1;
  LottieComposition? _composition;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final composition = await AssetLottie(_assetPath).load();
    if (!mounted) return;
    setState(() => _composition = composition);
    // The native splash stays up until now, so the handoff to this frame is seamless.
    FlutterNativeSplash.remove();

    // Hold for exactly one pass of the animation, read off the composition, so
    // swapping the asset for a longer or shorter one never truncates it.
    Future.delayed(composition.duration, () {
      if (!mounted) return;
      setState(() => _opacity = 0);
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        // A patient who signed in before skips Login entirely: supabase_flutter
        // restores and refreshes the stored session while this animation plays.
        if (SupabaseService.isSignedIn) {
          Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
          return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final composition = _composition;
    return Scaffold(
      backgroundColor: _backdrop,
      body: AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(milliseconds: 350),
        child: SizedBox.expand(
          child: composition == null
              ? const SizedBox.shrink()
              : Lottie(
                  composition: composition,
                  // The composition carries its own edge-to-edge background,
                  // so cover it fully rather than letterboxing it.
                  fit: BoxFit.cover,
                  repeat: false,
                ),
        ),
      ),
    );
  }
}
