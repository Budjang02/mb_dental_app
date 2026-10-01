// File: lib/screens/auth/login_screen.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/widgets/field_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/screens/auth/forgot_password_screen.dart';
import 'package:mb_dental_app/screens/auth/otp_verification_screen.dart';
import 'package:mb_dental_app/screens/auth/register_screen.dart';
import 'package:mb_dental_app/services/auth_service.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
import 'package:mb_dental_app/widgets/auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _networkMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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

  void _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _networkMessage = null;
    });
    final result = await AuthService.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _networkMessage = result.isRetryable ? result.message : null;
    });

    if (result.emailNotConfirmed) {
      await _finishEmailVerification();
      return;
    }
    if (!result.success) {
      showAppToast(context, result.message ?? 'Sign in failed.', isError: true);
      return;
    }
    // No push to the dashboard: `AuthGate` is watching the auth stream and
    // swaps this screen for the dashboard the moment the session opens. Only
    // anything stacked above the gate has to go.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// The account exists but its address was never confirmed. Like the
  /// website, send a fresh signup code and take the patient to the code
  /// screen instead of leaving them stuck here.
  Future<void> _finishEmailVerification() async {
    final email = _emailController.text.trim().toLowerCase();
    setState(() => _isLoading = true);
    final sent = await AuthService.resendSignupCode(email);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!sent.success) {
      showAppToast(
        context,
        sent.message ?? 'Please confirm your email address first, then sign in.',
        isError: true,
      );
      return;
    }

    final verified = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OtpVerificationScreen(destination: email)),
    );
    if (!mounted || verified != true) return;
    // Verifying opened the session; `AuthGate` takes it from here.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(initialEmail: _emailController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24.0, 32.0, 24.0, 16.0),
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
                              return Icon(CupertinoIcons.heart, size: 64, color: AppColors.primary);
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
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty) return 'Enter your email address.';
                            if (!email.contains('@') || !email.contains('.')) {
                              return 'Enter a valid email address.';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            labelText: 'Email Address',
                            prefixIcon: fieldIcon(FieldKind.email),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password Input
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_isPasswordVisible,
                          validator: (value) =>
                              (value == null || value.isEmpty) ? 'Enter your password.' : null,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: fieldIcon(FieldKind.password),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible ? TablerIcons.eye_off : TablerIcons.eye,
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
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Forgot Password Button
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _openForgotPassword,
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
                                borderRadius: BorderRadius.circular(12),
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
                        if (_networkMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _networkMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.textSecondary),
                          ),
                          TextButton.icon(
                            onPressed: _isLoading ? null : _handleLogin,
                            icon: const Icon(CupertinoIcons.arrow_clockwise, size: 17),
                            label: const Text('Retry'),
                          ),
                        ],
                        const SizedBox(height: 24),

                        // Direct Navigation Register Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                "Don't have an account?",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const RegisterScreen()),
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
                        const SizedBox(height: 8),

                        const AuthDivider(label: 'OR CONTINUE WITH'),
                        const SizedBox(height: 20),

                        SocialAuthRow(
                          onGoogle: () => _launchSocialUrl('https://accounts.google.com/signin'),
                          onFacebook: () => _launchSocialUrl('https://www.facebook.com/login'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: TermsNotice(leadIn: 'By signing in you agree to our'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
