// File: lib/screens/auth/login_screen.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mb_dental_app/app/routes.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/screens/auth/register_screen.dart'; // REQUIRED IMPORT
import 'package:mb_dental_app/widgets/app_dialog.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _resetEmailController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _resetEmailController.dispose();
    super.dispose();
  }

  Future<void> _launchSocialUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        showAppToast(context, 'Could not launch $url', isError: true);
      }
    }
  }

  // Trial/demo mode: skips validation and goes straight to the dashboard.
  // TODO: replace with a real auth call (e.g. POST /auth/login with
  // _emailController.text / _passwordController.text) once the backend
  // is ready, and only navigate on a successful response.
  Future<bool> _authenticateWithBackend() async {
    await Future.delayed(const Duration(milliseconds: 800));
    return true;
  }

  void _handleLogin() async {
    setState(() => _isLoading = true);
    final success = await _authenticateWithBackend();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
    }
  }

  void _showForgotPasswordDialog() {
    _resetEmailController.text = _emailController.text;
    showAppDialog(
      context,
      builder: (dialogContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Reset Password',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const AppDialogCloseButton(),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your registered email address to receive a password recovery link.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _resetEmailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: Icon(CupertinoIcons.mail, color: AppColors.primary, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    if (_resetEmailController.text.trim().isNotEmpty) {
                      Navigator.pop(dialogContext);
                      showAppToast(
                        context,
                        'Password reset link sent to ${_resetEmailController.text}',
                      );
                    }
                  },
                  child: const Text(
                    'Send Reset Link',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) => Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24.0, 32.0, 24.0, 24.0),
          child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // Brand Logo — swaps with the theme, light/dark each have
                  // an icon designed for that background.
                  SizedBox(
                    height: 108,
                    width: 108,
                    child: Image.asset(
                      ThemeController().isDark
                          ? 'assets/images/dark_mode_icon.png'
                          : 'assets/images/light_mode_icon.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          CupertinoIcons.heart_fill,
                          size: 64,
                          color: AppColors.primary,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Header Titles
                  Text(
                    'Mariano & Bolasoc',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dental Center',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Email Input
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(CupertinoIcons.mail, color: AppColors.primary, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password Input
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(CupertinoIcons.lock, color: AppColors.primary, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordVisible
                              ? CupertinoIcons.eye_slash
                              : CupertinoIcons.eye,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Forgot Password Button
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPasswordDialog,
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Main Login Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isLoading ? null : _handleLogin,
                      child: _isLoading
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : const Text(
                        'Login',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Divider
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14.0),
                        child: Text(
                          'OR CONTINUE WITH',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Social Media Buttons
                  Row(
                    children: [
                      // Google Button
                      Expanded(
                        child: InkWell(
                          onTap: () => _launchSocialUrl('https://accounts.google.com/signin'),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CustomPaint(painter: _GoogleLogoPainter()),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Google',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Facebook Button
                      Expanded(
                        child: InkWell(
                          onTap: () => _launchSocialUrl('https://www.facebook.com/login'),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.facebook_rounded, size: 22, color: Color(0xFF1877F2)),
                                const SizedBox(width: 8),
                                Text(
                                  'Facebook',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Direct Navigation Register Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account?",
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegisterScreen(),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Register',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Draws the actual Google "G" brand mark (the four-color G used on every
/// "Sign in with Google" button), traced from Google's official 48x48 vector
/// artwork so no external logo asset/network fetch is needed.
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  static const double _viewBoxSize = 48;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _viewBoxSize;
    canvas.save();
    canvas.scale(scale, scale);

    final paint = Paint()..style = PaintingStyle.fill;

    // Yellow arc
    paint.color = const Color(0xFFFFC107);
    canvas.drawPath(_yellowPath(), paint);

    // Red arc
    paint.color = const Color(0xFFFF3D00);
    canvas.drawPath(_redPath(), paint);

    // Green arc
    paint.color = const Color(0xFF4CAF50);
    canvas.drawPath(_greenPath(), paint);

    // Blue arc
    paint.color = const Color(0xFF1976D2);
    canvas.drawPath(_bluePath(), paint);

    canvas.restore();
  }

  Path _yellowPath() {
    return Path()
      ..moveTo(43.611, 20.083)
      ..lineTo(42, 20.083)
      ..lineTo(42, 20)
      ..lineTo(24, 20)
      ..lineTo(24, 28)
      ..lineTo(35.303, 28)
      ..cubicTo(33.654, 32.657, 29.223, 36, 24, 36)
      ..cubicTo(17.373, 36, 12, 30.627, 12, 24)
      ..cubicTo(12, 17.373, 17.373, 12, 24, 12)
      ..cubicTo(27.059, 12, 29.842, 13.154, 31.961, 15.039)
      ..lineTo(37.618, 9.382)
      ..cubicTo(34.046, 6.053, 29.268, 4, 24, 4)
      ..cubicTo(12.955, 4, 4, 12.955, 4, 24)
      ..cubicTo(4, 35.045, 12.955, 44, 24, 44)
      ..cubicTo(35.045, 44, 44, 35.045, 44, 24)
      ..cubicTo(44, 22.659, 43.862, 21.35, 43.611, 20.083)
      ..close();
  }

  Path _redPath() {
    return Path()
      ..moveTo(6.306, 14.691)
      ..lineTo(12.877, 19.51)
      ..cubicTo(14.655, 15.108, 18.961, 12, 24, 12)
      ..cubicTo(27.059, 12, 29.842, 13.154, 31.961, 15.039)
      ..lineTo(37.618, 9.382)
      ..cubicTo(34.046, 6.053, 29.268, 4, 24, 4)
      ..cubicTo(16.318, 4, 9.656, 8.337, 6.306, 14.691)
      ..close();
  }

  Path _greenPath() {
    return Path()
      ..moveTo(24, 44)
      ..cubicTo(29.166, 44, 33.86, 42.023, 37.409, 38.808)
      ..lineTo(31.219, 33.57)
      ..cubicTo(29.211, 35.091, 26.715, 36, 24, 36)
      ..cubicTo(18.798, 36, 14.381, 32.683, 12.717, 28.054)
      ..lineTo(6.195, 33.079)
      ..cubicTo(9.505, 39.556, 16.227, 44, 24, 44)
      ..close();
  }

  Path _bluePath() {
    return Path()
      ..moveTo(43.611, 20.083)
      ..lineTo(42, 20.083)
      ..lineTo(42, 20)
      ..lineTo(24, 20)
      ..lineTo(24, 28)
      ..lineTo(35.303, 28)
      ..cubicTo(34.511, 30.237, 33.072, 32.166, 31.216, 33.571)
      ..cubicTo(31.217, 33.57, 31.218, 33.57, 31.219, 33.569)
      ..lineTo(37.409, 38.807)
      ..cubicTo(36.971, 39.205, 44, 34, 44, 24)
      ..cubicTo(44, 22.659, 43.862, 21.35, 43.611, 20.083)
      ..close();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}