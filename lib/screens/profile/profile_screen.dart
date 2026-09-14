import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/widgets/field_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/repositories/clinic_api.dart';
import 'package:mb_dental_app/services/auth_service.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
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
              child: Icon(TablerIcons.logout, size: 26, color: AppColors.error),
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
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      // Clears the stored session so the next launch lands on
                      // Login. The app-wide auth listener handles the actual
                      // navigation once Supabase reports the sign-out.
                      await AuthService.signOut();
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
              leading: Icon(TablerIcons.camera, color: AppColors.primary),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndSetAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(TablerIcons.photo, color: AppColors.primary),
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
      await _repository.updateAvatar(picked.path);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Could not save your photo. Please try again.', isError: true);
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
            // Only what the clinic has actually published. A row with nothing
            // behind it used to dial an empty string.
            if (kClinicPhone.isNotEmpty) ...[
              _SupportRow(
                icon: TablerIcons.phone,
                label: 'Call the clinic',
                value: kClinicPhone,
                onTap: () {
                  Navigator.pop(dialogContext);
                  _launchSupport(
                    Uri(scheme: 'tel', path: kClinicPhone.replaceAll(RegExp(r'[^0-9+]'), '')),
                    'No dialer is available on this device.',
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
            if (kClinicEmail.isNotEmpty) ...[
              _SupportRow(
                icon: TablerIcons.mail,
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
            ],
            if (kClinicAddress.isNotEmpty)
              _SupportRow(
                icon: TablerIcons.map_pin,
                label: 'Visit us',
                value: kClinicAddress,
                onTap: () {
                  Navigator.pop(dialogContext);
                  _launchSupport(
                    Uri.https('www.google.com', '/maps/search/',
                        {'api': '1', 'query': kClinicAddress}),
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
                  Icon(TablerIcons.clock, size: 15, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      // The clinic writes its own hours; the weekday grid is
                      // only the fallback for when it has not.
                      ClinicCatalog().clinic.hours.isNotEmpty
                          ? ClinicCatalog().clinic.hours
                          : 'Open $clinicOperatingDaysLabel · $clinicHoursLabel',
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
                        Icon(TablerIcons.circle_check, size: 20, color: AppColors.primary),
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
                option(ThemeMode.system, TablerIcons.circle_half_2, 'System',
                    'Match the device light / dark setting.'),
                const SizedBox(height: 10),
                option(ThemeMode.light, TablerIcons.sun, 'Light', 'Always use the light theme.'),
                const SizedBox(height: 10),
                option(ThemeMode.dark, TablerIcons.moon, 'Dark', 'Always use the dark theme.'),
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
      // ClinicCatalog too: the Support row prints the clinic's own number, so
      // the page has to repaint once that has loaded.
      listenable: Listenable.merge([_repository, ClinicCatalog(), ThemeController()]),
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
                    icon: TablerIcons.user_circle,
                    title: 'Manage Profile',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                    ),
                  ),
                  _SettingRow(
                    icon: TablerIcons.lock,
                    title: 'Password & Security',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                    ),
                  ),
                  _SettingRow(
                    icon: TablerIcons.bell,
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
                    icon: TablerIcons.sun_moon,
                    title: 'Theme',
                    value: ThemeController().modeLabel,
                    onTap: _showThemePicker,
                  ),
                ]),
                const SizedBox(height: 22),
                _buildSectionLabel('Support'),
                _buildGroup([
                  _SettingRow(
                    icon: TablerIcons.messages,
                    title: 'Contact the Clinic',
                    value: kClinicPhone,
                    onTap: _showSupportSheet,
                  ),
                ]),
                const SizedBox(height: 22),
                _buildGroup([
                  _SettingRow(
                    icon: TablerIcons.logout,
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

  /// The stored photo is a URL (`profiles.avatar_url`, shared with the web
  /// portal); a path is only the local preview shown while an upload runs.
  /// Reading the URL as a file is what left the photo blank.
  ImageProvider? _avatarImage(String? avatarPath) {
    if (avatarPath == null || avatarPath.isEmpty) return null;
    if (avatarPath.startsWith('http://') || avatarPath.startsWith('https://')) {
      return NetworkImage(avatarPath);
    }
    final file = File(avatarPath);
    return file.existsSync() ? FileImage(file) : null;
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
                  backgroundImage: _avatarImage(avatarPath),
                  child: _avatarImage(avatarPath) == null
                      ? Icon(TablerIcons.user, size: 34, color: AppColors.primary)
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
                    child: const Icon(TablerIcons.plus, size: 12, color: Colors.white),
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
              Icon(TablerIcons.user_plus, size: 18, color: AppColors.primary),
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
              Icon(TablerIcons.chevron_right, size: 15, color: AppColors.primary),
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
                Icon(TablerIcons.chevron_right, size: 16, color: AppColors.textSecondary),
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
              Icon(TablerIcons.chevron_right, size: 14, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
