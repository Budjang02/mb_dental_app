import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/notification_settings.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/repositories/notification_feed.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';

/// Push notification preferences: appointment reminders and status updates.
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = NotificationSettings();
    final repository = PatientRepository();
    return ListenableBuilder(
      listenable: Listenable.merge([settings, repository, ThemeController()]),
      builder: (context, _) {
        final shared = repository.notificationPrefs;
        void setShared(NotificationPrefs next) =>
            repository.setNotificationPrefs(next);
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: const Text('Notifications')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              // Shared with the website through `notification_prefs`: these
              // decide what is on the bell, and so what it counts, everywhere
              // this account signs in.
              Text(
                'What your notification list shows, here and on the M&B Dental website.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _ToggleTile(
                      icon: CupertinoIcons.bell,
                      title: 'Notifications',
                      subtitle: 'Turn the whole list and the badge on or off.',
                      value: shared.enabled,
                      onChanged: (on) =>
                          setShared(shared.copyWith(enabled: on)),
                    ),
                    Divider(height: 1, indent: 60, color: AppColors.border),
                    _ToggleTile(
                      icon: CupertinoIcons.calendar,
                      title: 'Appointment reminders',
                      subtitle:
                          'Confirmations, and a reminder in the 24 hours before a visit.',
                      value: shared.appointment,
                      onChanged: shared.enabled
                          ? (on) => setShared(shared.copyWith(appointment: on))
                          : null,
                    ),
                    Divider(height: 1, indent: 60, color: AppColors.border),
                    _ToggleTile(
                      icon: CupertinoIcons.list_bullet,
                      title: 'Treatment plan updates',
                      subtitle:
                          'When your dentist adds to or changes your plan.',
                      value: shared.plan,
                      onChanged: shared.enabled
                          ? (on) => setShared(shared.copyWith(plan: on))
                          : null,
                    ),
                    Divider(height: 1, indent: 60, color: AppColors.border),
                    _ToggleTile(
                      icon: CupertinoIcons.doc_text,
                      title: 'Billing & receipts',
                      subtitle: 'Receipts for payments recorded at the clinic.',
                      value: shared.billing,
                      onChanged: shared.enabled
                          ? (on) => setShared(shared.copyWith(billing: on))
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Choose what Mariano & Bolasoc Dental can notify you about on this device.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _ToggleTile(
                      icon: CupertinoIcons.bell_fill,
                      title: 'Appointment Reminders',
                      subtitle: 'Get a nudge before your upcoming visit.',
                      value: settings.appointmentReminders,
                      onChanged: settings.setAppointmentReminders,
                    ),
                    Divider(height: 1, indent: 60, color: AppColors.border),
                    _ToggleTile(
                      icon: CupertinoIcons.checkmark_seal_fill,
                      title: 'Status Updates',
                      subtitle: 'Confirmations, reschedules and cancellations.',
                      value: settings.statusUpdates,
                      onChanged: settings.setStatusUpdates,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      secondary: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }
}
