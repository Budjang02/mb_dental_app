import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../app/theme.dart';
import '../auth/login_screen.dart';

/// Full-bleed animated splash. The Lottie file's canvas is already sized for
/// a phone screen, so it's rendered at its natural proportions (no extra
/// zoom/crop) and loops for as long as the app takes to get ready.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _opacity = 1;

  @override
  void initState() {
    super.initState();
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
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(milliseconds: 350),
        child: SizedBox.expand(
          child: Lottie.asset(
            'assets/animations/animation_splash.json',
            fit: BoxFit.contain,
            repeat: true,
          ),
        ),
      ),
    );
  }
}
