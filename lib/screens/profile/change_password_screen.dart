import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final PatientRepository _repository = PatientRepository();
  bool _isSaving = false;
  bool _currentHidden = true;
  bool _newHidden = true;
  bool _confirmHidden = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final success = await _repository.changePassword(
      currentPassword: _currentController.text,
      newPassword: _newController.text,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      showAppToast(context, 'Password updated.');
      Navigator.pop(context);
    } else {
      showAppToast(context, 'Could not update password. Try again.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Change Password')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Change Password',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose a password you do not use anywhere else. You stay signed in on this device.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 24),
                _buildSection(
                  title: 'Current Password',
                  description: 'Confirm it is you before anything changes.',
                  fields: [
                    _buildField(
                      label: 'CURRENT PASSWORD',
                      hint: 'Enter current password',
                      icon: CupertinoIcons.lock_fill,
                      controller: _currentController,
                      obscured: _currentHidden,
                      onToggle: () => setState(() => _currentHidden = !_currentHidden),
                      validator: (v) => (v == null || v.isEmpty) ? 'Enter your current password' : null,
                    ),
                  ],
                ),
                const _DashedDivider(),
                _buildSection(
                  title: 'New Password',
                  description: 'Use 8+ characters with letters and numbers.',
                  fields: [
                    _buildField(
                      label: 'NEW PASSWORD',
                      hint: 'Create a new password',
                      icon: Icons.key_rounded,
                      controller: _newController,
                      obscured: _newHidden,
                      onToggle: () => setState(() => _newHidden = !_newHidden),
                      validator: _validateNewPassword,
                    ),
                    const SizedBox(height: 18),
                    _buildField(
                      label: 'CONFIRM NEW PASSWORD',
                      hint: 'Re-enter new password',
                      icon: Icons.key_rounded,
                      controller: _confirmController,
                      obscured: _confirmHidden,
                      onToggle: () => setState(() => _confirmHidden = !_confirmHidden),
                      validator: (v) => v != _newController.text ? 'Passwords do not match' : null,
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Update Password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _validateNewPassword(String? value) {
    if (value == null || value.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(value)) return 'Include at least one letter';
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'Include at least one number';
    return null;
  }

  /// Reference layout puts the section label and its explanation beside the
  /// inputs. There is no room for two columns on a phone, so the pair stacks
  /// below ~560px wide and sits side by side on tablets.
  Widget _buildSection({
    required String title,
    required String description,
    required List<Widget> fields,
  }) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 560) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 200, child: heading),
              const SizedBox(width: 32),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: fields)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            const SizedBox(height: 16),
            ...fields,
          ],
        );
      },
    );
  }

  Widget _buildField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    required bool obscured,
    required VoidCallback onToggle,
    required FormFieldValidator<String> validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscured,
          style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 14, color: AppColors.textSecondary.withOpacity(0.8)),
            filled: true,
            fillColor: AppColors.surface,
            prefixIcon: Icon(icon, size: 18, color: AppColors.textSecondary),
            prefixIconConstraints: const BoxConstraints(minWidth: 44),
            suffixIcon: IconButton(
              icon: Icon(
                obscured ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                size: 18,
                color: AppColors.textSecondary,
              ),
              onPressed: onToggle,
              tooltip: obscured ? 'Show password' : 'Hide password',
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.primary, width: 1.6),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}

/// Hairline dashed rule separating the two sections, as in the reference.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: CustomPaint(
        size: const Size(double.infinity, 1),
        painter: _DashedLinePainter(color: AppColors.border),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;

  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 5.0;
    const gapWidth = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + gapWidth;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) => oldDelegate.color != color;
}
