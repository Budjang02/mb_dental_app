import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../app/notification_style.dart';
import '../app/theme.dart';
import '../app/theme_controller.dart';
import '../models/notification.dart';
import '../repositories/notification_feed.dart';

/// One notice, laid out like a row of the website's bell and Notifications
/// section (`.notif-drop-item` in css/app-shell.css): a tinted icon tile, then
/// three left-ranged lines — who and when, what happened, the details.
///
/// Unread rows carry a 3px teal bar on the left edge and a bold title. Reading
/// removes both; the icon and its colour stay, because they say what kind of
/// event it was, not whether it has been seen. Sizes are the website's,
/// stepped up for a phone: a 36px tile rather than 34, and text that stays
/// readable at arm's length.
class NotificationRow extends StatelessWidget {
  final NotificationItem notification;
  final VoidCallback? onTap;

  /// Clamps the details to two lines, for the bell's dropdown.
  final bool compact;

  const NotificationRow({
    super.key,
    required this.notification,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final dark = ThemeController().isDark;
    final tone = NotificationStyle.toneOf(n.event);
    final byline = NotificationFeed.byline(n, DateTime.now());

    return Semantics(
      button: onTap != null,
      label: n.isRead ? null : 'Unread',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  compact ? 12 : 14,
                  16,
                  compact ? 12 : 14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: NotificationStyle.tileColor(tone, dark: dark),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: FaIcon(
                        NotificationStyle.iconOf(n.event),
                        size: 15,
                        color: NotificationStyle.iconColor(tone, dark: dark),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (byline.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                byline,
                                style: TextStyle(
                                  fontSize: 12,
                                  // The website's `.ndi-time` slate, in both themes.
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          Text(
                            n.title,
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.3,
                              fontWeight: n.isRead
                                  ? FontWeight.w600
                                  : FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (n.body.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                n.body,
                                maxLines: compact ? 2 : null,
                                overflow: compact
                                    ? TextOverflow.ellipsis
                                    : null,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.45,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!n.isRead)
                Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 3,
                    decoration: const BoxDecoration(
                      color: NotificationStyle.unreadIndicator,
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
