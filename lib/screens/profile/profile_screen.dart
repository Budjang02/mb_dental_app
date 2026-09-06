import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/app/routes.dart';
import 'package:mb_dental_app/data/clinic_catalog.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';
import 'notification_settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final PatientRepository _repository = PatientRepository();

  void _showLogoutDialog(BuildContext context) {
    showAppDialog(
      context,
      maxWidth: 360,
      builder: (dialogContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(CupertinoIcons.square_arrow_right, size: 26, color: AppColors.error),
            ),
            const SizedBox(height: 18),
            Text(
              'Log out?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'You will be signed out on this device and returned to the sign-in page.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.background,
                      foregroundColor: AppColors.textPrimary,
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: AppColors.border),
                      ),
                    ),
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text(
                      'Stay signed in',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
                    },
                    child: const Text('Log out'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(CupertinoIcons.camera, color: AppColors.primary),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndSetAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(CupertinoIcons.photo, color: AppColors.primary),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndSetAvatar(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSetAvatar(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 800);
      if (picked == null || !mounted) return;
      _repository.updateAvatar(picked.path);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Could not set photo: $e', isError: true);
    }
  }

  /// Theme picker: System (follows the device setting), Light or Dark.
  /// Presented as a floating window rather than a sheet so it reads as a
  /// small settings dialog over the profile page.
  /// Opens the device's own dialer / mail client / maps app. A device without
  /// a handler for the scheme (an emulator, usually) gets a toast rather than
  /// a silent no-op.
  Future<void> _launchSupport(Uri uri, String failureMessage) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      showAppToast(context, failureMessage, isError: true);
    }
  }

  void _showSupportSheet() {
    showAppDialog(
      context,
      maxWidth: 380,
      builder: (dialogContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Clinic Support',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ),
                const AppDialogCloseButton(),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              kClinicName,
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            _SupportRow(
              icon: CupertinoIcons.phone,
              label: 'Call the clinic',
              value: kClinicPhone,
              onTap: () {
                Navigator.pop(dialogContext);
                _launchSupport(
                  Uri(scheme: 'tel', path: kClinicPhone.replaceAll(' ', '')),
                  'No dialer is available on this device.',
                );
              },
            ),
            const SizedBox(height: 10),
            _SupportRow(
              icon: CupertinoIcons.mail,
              label: 'Email us',
              value: kClinicEmail,
              onTap: () {
                Navigator.pop(dialogContext);
                _launchSupport(
                  Uri(scheme: 'mailto', path: kClinicEmail),
                  'No mail app is available on this device.',
                );
              },
            ),
            const SizedBox(height: 10),
            _SupportRow(
              icon: CupertinoIcons.map_pin_ellipse,
              label: 'Visit us',
              value: kClinicAddress,
              onTap: () {
                Navigator.pop(dialogContext);
                _launchSupport(
                  Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': kClinicAddress}),
                  'No maps app is available on this device.',
                );
              },
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(CupertinoIcons.clock, size: 15, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Open $clinicOperatingDaysLabel · $clinicHoursLabel',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showThemePicker() {
    showAppDialog(
      context,
      maxWidth: 360,
      builder: (dialogContext) => ListenableBuilder(
        listenable: ThemeController(),
        builder: (context, _) {
          final current = ThemeController().mode;

          Widget option(ThemeMode mode, IconData icon, String label, String description) {
            final selected = current == mode;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  ThemeController().setMode(mode);
                  Navigator.pop(dialogContext);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary.withOpacity(0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? AppColors.primary.withOpacity(0.45) : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 22, color: selected ? AppColors.primary : AppColors.textSecondary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              description,
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(CupertinoIcons.checkmark_alt_circle_fill, size: 20, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Theme',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                    ),
                    const AppDialogCloseButton(),
                  ],
                ),
                const SizedBox(height: 14),
                option(ThemeMode.system, CupertinoIcons.circle_lefthalf_fill, 'System',
                    'Match the device light / dark setting.'),
                const SizedBox(height: 10),
                option(ThemeMode.light, CupertinoIcons.sun_max_fill, 'Light', 'Always use the light theme.'),
                const SizedBox(height: 10),
                option(ThemeMode.dark, CupertinoIcons.moon_fill, 'Dark', 'Always use the dark theme.'),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_repository, ThemeController()]),
      builder: (context, _) {
        final patient = _repository.patient;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Profile'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 104),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIdentityCard(patient.fullName, patient.email, patient.avatarPath),
                if (!patient.isProfileComplete) ...[
                  const SizedBox(height: 12),
                  _buildCompletionNudge(patient.missingProfileFields),
                ],
                const SizedBox(height: 22),
                _buildSectionLabel('Account'),
                _buildGroup([
                  _SettingRow(
                    icon: CupertinoIcons.person_crop_circle,
                    title: 'Manage Profile',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                    ),
                  ),
                  _SettingRow(
                    icon: CupertinoIcons.lock,
                    title: 'Password & Security',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                    ),
                  ),
                  _SettingRow(
                    icon: CupertinoIcons.bell,
                    title: 'Notifications',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
                    ),
                  ),
                ]),
                const SizedBox(height: 22),
                _buildSectionLabel('Preferences'),
                _buildGroup([
                  _SettingRow(
                    icon: CupertinoIcons.circle_lefthalf_fill,
                    title: 'Theme',
                    value: ThemeController().modeLabel,
                    onTap: _showThemePicker,
                  ),
                ]),
                const SizedBox(height: 22),
                _buildSectionLabel('Support'),
                _buildGroup([
                  _SettingRow(
                    icon: CupertinoIcons.chat_bubble_2,
                    title: 'Contact the Clinic',
                    value: kClinicPhone,
                    onTap: _showSupportSheet,
                  ),
                ]),
                const SizedBox(height: 22),
                _buildGroup([
                  _SettingRow(
                    icon: CupertinoIcons.square_arrow_right,
                    title: 'Log Out',
                    color: AppColors.error,
                    showChevron: false,
                    onTap: () => _showLogoutDialog(context),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIdentityCard(String fullName, String email, String? avatarPath) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _pickAvatar,
            borderRadius: BorderRadius.circular(42),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primary.withOpacity(0.12),
                  backgroundImage: avatarPath != null ? FileImage(File(avatarPath)) : null,
                  child: avatarPath == null
                      ? Icon(CupertinoIcons.person_fill, size: 34, color: AppColors.primary)
                      : null,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                    child: const Icon(CupertinoIcons.add, size: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Streamlined sign-up leaves date of birth, gender and address blank. This
  /// says which are still outstanding rather than blocking the patient at
  /// registration for details the clinic can also take at check-in.
  Widget _buildCompletionNudge(List<String> missing) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EditProfileScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(CupertinoIcons.person_badge_plus, size: 18, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Complete your profile',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Still needed: ${missing.join(', ')}',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_right, size: 15, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      ),
    );
  }

  /// Rows share one rounded card with hairline dividers between them, matching
  /// the grouped-settings look of the reference design.
  Widget _buildGroup(List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 52, color: AppColors.border),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final Color? color;
  final bool showChevron;
  final VoidCallback onTap;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.color,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? AppColors.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color ?? AppColors.textPrimary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: foreground),
                ),
              ),
              if (value != null) ...[
                Text(
                  value!,
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 8),
              ],
              if (showChevron)
                Icon(CupertinoIcons.chevron_right, size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tappable contact line in the clinic support sheet.
class _SupportRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SupportRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_right, size: 14, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
