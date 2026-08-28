import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/notification.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/screens/dashboard/home_tab.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = PatientRepository();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Notifications')),
      body: ListenableBuilder(
        listenable: Listenable.merge([repository, ThemeController()]),
        builder: (context, _) {
          final notifications = repository.notifications;
          if (notifications.isEmpty) {
            return Center(
              child: Text('No notifications yet.', style: TextStyle(color: AppColors.textSecondary)),
            );
          }

          final grouped = <String, List<NotificationItem>>{};
          for (final n in notifications) {
            grouped.putIfAbsent(formatNotificationDate(n.createdAt), () => []).add(n);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              for (final entry in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, top: 6),
                  child: Text(
                    entry.key,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < entry.value.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: AppColors.border),
                        _NotificationTile(notification: entry.value[i], repository: repository),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationItem notification;
  final PatientRepository repository;

  const _NotificationTile({required this.notification, required this.repository});

  @override
  Widget build(BuildContext context) {
    final n = notification;
    return InkWell(
      onTap: () {
        repository.markNotificationRead(n.id);
        showNotificationDetailDialog(context, n);
      },
      child: Container(
        color: n.isRead ? Colors.transparent : AppColors.primary.withOpacity(0.05),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: notificationColor(n).withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(notificationIcon(n), color: notificationColor(n), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: n.isRead ? FontWeight.w600 : FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (!n.isRead)
                        Container(
                          margin: const EdgeInsets.only(left: 8, top: 4),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(n.body, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(CupertinoIcons.clock, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        formatNotificationTime(n.createdAt),
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
