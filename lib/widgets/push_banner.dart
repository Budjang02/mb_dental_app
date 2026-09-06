import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/notification.dart';
import '../repositories/patient_repository.dart';
import '../services/push_notification_service.dart';
import 'app_toast.dart';

/// Wraps the whole app so a real-time alert can drop in over any screen, the
/// way a system push notification would. Mounted once from `MaterialApp.builder`.
class PushBannerHost extends StatelessWidget {
  final Widget child;

  const PushBannerHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ListenableBuilder(
            listenable: PushNotificationService(),
            builder: (context, _) {
              final item = PushNotificationService().latest;
              return _PushBanner(
                // Keying on the id restarts the entry animation for each new
                // alert instead of silently swapping the text of the old one.
                key: ValueKey(item?.id),
                item: item,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PushBanner extends StatefulWidget {
  final NotificationItem? item;

  const _PushBanner({super.key, required this.item});

  @override
  State<_PushBanner> createState() => _PushBannerState();
}

class _PushBannerState extends State<_PushBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    if (widget.item != null) _show();
  }

  Future<void> _show() async {
    // A toast occupies the same strip at the top of the screen. Let it finish
    // before dropping in, rather than the two landing on top of each other.
    for (var waited = 0; appToastCount.value > 0 && waited < 4000; waited += 200) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
    }
    if (!mounted) return;

    await _controller.forward();
    await Future.delayed(const Duration(milliseconds: 3600));
    if (!mounted) return;
    await _dismiss();
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    final id = widget.item?.id;
    if (id != null) PushNotificationService().clear(id);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    if (item == null) return const SizedBox.shrink();

    final topInset = MediaQuery.of(context).padding.top;

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic)),
      child: FadeTransition(
        opacity: _controller,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, topInset + 10, 16, 0),
          child: Material(
            color: Colors.transparent,
            child: Dismissible(
              key: ValueKey('push-${item.id}'),
              direction: DismissDirection.up,
              onDismissed: (_) => PushNotificationService().clear(item.id),
              child: GestureDetector(
                onTap: () {
                  PatientRepository().markNotificationRead(item.id);
                  _dismiss();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.20),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(CupertinoIcons.bell_fill, size: 15, color: AppColors.primary),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.body,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.35,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
