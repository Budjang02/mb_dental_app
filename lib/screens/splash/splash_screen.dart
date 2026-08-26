import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:lottie/lottie.dart';
import '../../app/theme.dart';
import '../auth/login_screen.dart';

/// Full-bleed animated splash. The Lottie composition is decoded before this
/// widget paints anything (see [initState]), and the native OS splash is
/// kept pinned until that decode finishes — so the very first thing drawn is
/// an animation frame, never a bare plain-color screen. It then loops for as
/// long as the app takes to get ready.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _assetPath = 'assets/animations/animation_splash.json';

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

    // Total time the splash stays up while the animation loops. Long enough
    // to see it repeat at least once (the file itself runs ~3s per cycle).
    Future.delayed(const Duration(milliseconds: 4200), () {
      if (!mounted) return;
      setState(() => _opacity = 0);
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
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
      backgroundColor: AppColors.primary,
      body: AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(milliseconds: 350),
        child: SizedBox.expand(
          child: composition == null
              ? const SizedBox.shrink()
              : Lottie(
                  composition: composition,
                  fit: BoxFit.contain,
                  repeat: true,
                ),
        ),
      ),
    );
  }
}
