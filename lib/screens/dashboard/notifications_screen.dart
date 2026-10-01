import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/notification.dart';
import 'package:mb_dental_app/repositories/notification_feed.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/screens/dashboard/notification_actions.dart';
import 'package:mb_dental_app/screens/profile/notification_settings_screen.dart';
import 'package:mb_dental_app/widgets/notification_row.dart';

/// The full list — the website's Notifications section. Grouped under day
/// headings, "Mark all as read" in the app bar, swipe a row away to delete it
/// (the website's per-row delete, synced through `notif_dismiss`).
///
/// Opening the list marks nothing read; only tapping a notice, or "Mark all as
/// read", does.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // The read state may have changed on the website while this was closed,
    // and a realtime event missed while the socket was down is not replayed.
    unawaited(PatientRepository().refreshNotifications());
  }

  @override
  Widget build(BuildContext context) {
    final repository = PatientRepository();
    return ListenableBuilder(
      listenable: Listenable.merge([repository, ThemeController()]),
      builder: (context, _) {
        final enabled = repository.notificationPrefs.enabled;
        final notifications = repository.notifications;
        final unread = repository.unreadNotificationCount;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Notifications'),
            actions: [
              if (enabled && unread > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    onPressed: repository.markAllNotificationsRead,
                    icon: Icon(
                      Icons.done_all_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    label: Text(
                      'Mark all as read',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: repository.refreshNotifications,
            child: !enabled
                ? _Message(
                    title: 'Notifications are turned off',
                    body:
                        'Turn them on to see appointment reminders and receipts again.',
                    action: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NotificationSettingsScreen(),
                        ),
                      ),
                      child: const Text('Open Settings'),
                    ),
                  )
                : notifications.isEmpty
                ? const _Message(
                    title: 'No notifications yet',
                    body: 'Notifications will appear here once available.',
                  )
                : _List(notifications: notifications, repository: repository),
          ),
        );
      },
    );
  }
}

class _List extends StatelessWidget {
  final List<NotificationItem> notifications;
  final PatientRepository repository;

  const _List({required this.notifications, required this.repository});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Runs of consecutive notices under one heading, in feed order — the
    // website's `_notifDayBucket` grouping.
    final groups = <(String, List<NotificationItem>)>[];
    for (final n in notifications) {
      final bucket = NotificationFeed.dayBucket(n, now);
      if (groups.isEmpty || groups.last.$1 != bucket) groups.add((bucket, []));
      groups.last.$2.add(n);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        for (final (bucket, items) in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(
              bucket,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.border),
                  Dismissible(
                    key: ValueKey(items[i].id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      color: Colors.redAccent,
                      child: const Icon(
                        CupertinoIcons.trash,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    onDismissed: (_) =>
                        repository.dismissNotification(items[i].id),
                    child: NotificationRow(
                      notification: items[i],
                      onTap: () => openNotification(
                        context,
                        items[i],
                        onNotificationsScreen: true,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String title;
  final String body;
  final Widget? action;

  const _Message({required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) {
    // Scrollable so pull-to-refresh still works on an empty list.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 120, 32, 32),
      children: [
        Icon(
          CupertinoIcons.bell_slash,
          size: 36,
          color: AppColors.textSecondary.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        if (action != null) ...[
          const SizedBox(height: 12),
          Center(child: action!),
        ],
      ],
    );
  }
}
