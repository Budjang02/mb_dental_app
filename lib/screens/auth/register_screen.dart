// File: lib/screens/auth/register_screen.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mb_dental_app/app/routes.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/screens/auth/otp_verification_screen.dart';
import 'package:mb_dental_app/widgets/app_overlays.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
import 'package:mb_dental_app/widgets/auth_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  static const Color _tealColor = Color(0xFF0D9488);

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

  /// The account is only created once the code lands. Verifying first means a
  /// mistyped number never becomes a patient record nobody can reach.
  void _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final verified = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OtpVerificationScreen(destination: email)),
    );
    if (!mounted || verified != true) return;

    setState(() => _isLoading = true);

    // Sign-up captures name and email only. Phone, date of birth, gender and
    // address are filled in later under Profile, or at clinic check-in — the
    // completion nudge there lists whatever is still blank.
    await PatientRepository().registerPatient(
      fullName: _fullNameController.text.trim(),
      email: email,
      phone: '',
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    await showSuccessOverlay(
      context,
      message:
          'Your account is ready. Complete your profile any time from the '
          'Profile tab.',
    );
    if (!mounted) return;

    Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  top: statusBarHeight + 32, // Added top spacing above top branding
                  left: 24.0,
                  right: 24.0,
                  bottom: 16.0,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Enlarged Top Branding Row (Bigger than Create Account text)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: SizedBox(
                              height: 32,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'Mariano & Bolasoc',
                                  style: TextStyle(
                                    fontSize: 30, // Scaled larger than Create Account (26px)
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    height: 1.0,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Brand logo — swaps with the theme, and matches the
                          // branding text's height exactly (both boxed at 32). Nudged
                          // up so it sits on the wordmark's optical centre: the text
                          // box reserves room for descenders that "Mariano & Bolasoc"
                          // never uses, which otherwise leaves the logo riding low.
                          Transform.translate(
                            offset: const Offset(0, -4),
                            child: SizedBox(
                              height: 32,
                              width: 32,
                              child: Image.asset(
                                ThemeController().isDark
                                    ? 'assets/images/dark_mode_icon.png'
                                    : 'assets/images/light_mode_icon.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    CupertinoIcons.heart,
                                    size: 32,
                                    color: _tealColor,
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Create Account Title Section
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Create Account',
                              style: TextStyle(
                                fontSize: 24, // Proportionately sized under branding
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                                color: _tealColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Fill in your details to get started',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Full Name Input
                      TextFormField(
                        controller: _fullNameController,
                        decoration: InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: Icon(
                            CupertinoIcons.person,
                            color: AppColors.primary,
                            size: 24,
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
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your full name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Email Input
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          prefixIcon: Icon(CupertinoIcons.mail, color: AppColors.primary, size: 24),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!value.contains('@')) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Password Input
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(CupertinoIcons.lock, color: AppColors.primary, size: 24),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordVisible ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                              color: AppColors.textSecondary,
                              size: 24,
                            ),
                            onPressed: () {
                              setState(() => _isPasswordVisible = !_isPasswordVisible);
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
                        validator: (value) {
                          if (value == null || value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Confirm Password Input
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: !_isConfirmPasswordVisible,
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          prefixIcon: Icon(
                            CupertinoIcons.lock_shield,
                            color: AppColors.primary,
                            size: 24,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isConfirmPasswordVisible
                                  ? CupertinoIcons.eye_slash
                                  : CupertinoIcons.eye,
                              color: AppColors.textSecondary,
                              size: 24,
                            ),
                            onPressed: () {
                              setState(
                                () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
                              );
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
                        validator: (value) {
                          if (value != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // Create Account Action Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _tealColor,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isLoading ? null : _handleRegister,
                          child: _isLoading
                              ? const CupertinoActivityIndicator(color: Colors.white)
                              : const Text(
                                  'Create Account',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              "Already have an account?",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Sign In',
                              style: TextStyle(
                                color: _tealColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      const AuthDivider(label: 'OR SIGN UP WITH'),
                      const SizedBox(height: 20),

                      SocialAuthRow(
                        onGoogle: () => _launchSocialUrl('https://accounts.google.com/signup'),
                        onFacebook: () => _launchSocialUrl('https://www.facebook.com/r.php'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: TermsNotice(leadIn: 'By signing up, you agree to our'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
