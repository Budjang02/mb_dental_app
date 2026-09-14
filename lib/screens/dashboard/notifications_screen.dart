import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/notification.dart';
import 'package:mb_dental_app/repositories/notification_feed.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/screens/dashboard/home_tab.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the centre re-reads the alerts: the read state may have been
    // changed on the web platform while this screen was closed, and a realtime
    // event that arrived while the socket was down is not replayed.
    unawaited(PatientRepository().refreshNotifications());
  }

  @override
  Widget build(BuildContext context) {
    final repository = PatientRepository();
    // The whole Scaffold rebuilds on repository changes so the app bar's
    // "Mark all as read" action disappears the moment nothing is unread.
    return ListenableBuilder(
      listenable: Listenable.merge([repository, ThemeController()]),
      builder: (context, _) {
        final notifications = repository.notifications;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Notifications'),
            actions: [
              if (repository.unreadNotificationCount > 0)
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
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: Builder(
            builder: (context) {
              if (notifications.isEmpty) {
                return Center(
                  child: Text(
                    'No notifications yet.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }

              final grouped = <String, List<NotificationItem>>{};
              for (final n in notifications) {
                grouped
                    .putIfAbsent(formatNotificationDate(n.createdAt), () => [])
                    .add(n);
              }

              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: repository.refreshNotifications,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    for (final entry in grouped.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10, top: 6),
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
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
                              if (i > 0)
                                Divider(height: 1, color: AppColors.border),
                              // Derived notices can be dismissed; the website
                              // hides the same key, via `notif_dismiss`.
                              if (NotificationFeed.isDerived(entry.value[i].id))
                                Dismissible(
                                  key: ValueKey(entry.value[i].id),
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
                                      repository.dismissNotification(entry.value[i].id),
                                  child: _NotificationTile(
                                    notification: entry.value[i],
                                    repository: repository,
                                  ),
                                )
                              else
                                _NotificationTile(
                                  notification: entry.value[i],
                                  repository: repository,
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationItem notification;
  final PatientRepository repository;

  const _NotificationTile({
    required this.notification,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    final n = notification;
    return InkWell(
      onTap: () {
        repository.markNotificationRead(n.id);
        showNotificationDetailDialog(context, n);
      },
      child: Container(
        color: n.isRead
            ? Colors.transparent
            : AppColors.primary.withOpacity(0.05),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 14),
              child: FaIcon(notificationIconFor(n), size: 18, color: AppColors.primary),
            ),
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
                            fontSize: 16,
                            fontWeight: n.isRead
                                ? FontWeight.w600
                                : FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (!n.isRead)
                        Container(
                          margin: const EdgeInsets.only(left: 8, top: 4),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n.body,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [

                      Text(
                        formatNotificationTime(n.createdAt),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
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
