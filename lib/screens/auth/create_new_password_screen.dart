import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/theme_controller.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_overlays.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/auth_widgets.dart';

/// Step two of recovery: set the replacement. Pops `true` once the change is
/// confirmed, which tells [ForgotPasswordScreen] recovery is finished.
class CreateNewPasswordScreen extends StatefulWidget {
  /// The account being reset, carried through from the previous step.
  final String email;

  const CreateNewPasswordScreen({super.key, required this.email});

  @override
  State<CreateNewPasswordScreen> createState() => _CreateNewPasswordScreenState();
}

class _CreateNewPasswordScreenState extends State<CreateNewPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmVisible = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    showBlockingLoader(context, 'Updating your password, please wait...');

    // Works off whichever session is already open: the recovery session the
    // emailed link established, or the patient's normal one when they reach
    // this screen from Profile. Without a session Supabase rejects the call,
    // which is exactly what stops anyone resetting an account they do not own.
    final result = await AuthService.updatePassword(_passwordController.text);
    if (!mounted) return;
    hideBlockingLoader(context);

    if (!result.success) {
      showAppToast(context, result.message ?? 'Could not update your password.', isError: true);
      return;
    }

    await showSuccessOverlay(
      context,
      message: 'Your password has been changed. You can now sign in with your '
          'new password.',
    );
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          leading: IconButton(
            icon: const Icon(CupertinoIcons.chevron_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 72,
                    width: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withOpacity(0.12),
                    ),
                    child: Icon(
                      CupertinoIcons.lock_shield,
                      size: 32,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Create New Password',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Set a new password for ${widget.email}. It must be at least '
                    '6 characters long.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: authInputDecoration(
                      label: 'New Password',
                      icon: CupertinoIcons.lock,
                      suffixIcon: _visibilityToggle(
                        isVisible: _isPasswordVisible,
                        onTap: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
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
                  TextFormField(
                    controller: _confirmController,
                    obscureText: !_isConfirmVisible,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: authInputDecoration(
                      label: 'Confirm Password',
                      icon: CupertinoIcons.lock_shield,
                      suffixIcon: _visibilityToggle(
                        isVisible: _isConfirmVisible,
                        onTap: () => setState(() => _isConfirmVisible = !_isConfirmVisible),
                      ),
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _submit,
                      child: const Text(
                        'Reset Password',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _visibilityToggle({required bool isVisible, required VoidCallback onTap}) {
    return IconButton(
      icon: Icon(
        isVisible ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
        color: AppColors.textSecondary,
        size: 22,
      ),
      onPressed: onTap,
    );
  }
}
