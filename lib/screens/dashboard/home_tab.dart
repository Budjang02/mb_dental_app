import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/models/notification.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/screens/appointments/appointments_screen.dart';
import 'package:mb_dental_app/screens/appointments/book_appointment_screen.dart';
import 'package:mb_dental_app/screens/dashboard/notifications_screen.dart';
import 'package:mb_dental_app/screens/wallet/transaction_history_screen.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';
import 'package:mb_dental_app/widgets/appointment_detail_sheet.dart';
import 'package:mb_dental_app/widgets/transaction_detail_sheet.dart';

const List<String> _monthNames = [
  'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
  'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
];

String _formatDateHeading(DateTime date) => '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';

/// Picks an icon + accent color for a notification based on keywords in its
/// title, so the list reads at a glance instead of every row looking the same.
IconData notificationIcon(NotificationItem n) {
  final title = n.title.toLowerCase();
  if (title.contains('payment') || title.contains('wallet') || title.contains('receipt')) {
    return CupertinoIcons.creditcard_fill;
  }
  if (title.contains('reminder')) {
    return CupertinoIcons.bell_fill;
  }
  if (title.contains('appointment') || title.contains('confirm') || title.contains('schedule')) {
    return CupertinoIcons.calendar;
  }
  return CupertinoIcons.sparkles;
}

Color notificationColor(NotificationItem n) {
  final title = n.title.toLowerCase();
  if (title.contains('payment') || title.contains('wallet') || title.contains('receipt')) {
    return AppColors.success;
  }
  if (title.contains('reminder')) {
    return AppColors.warning;
  }
  return AppColors.primary;
}

String formatNotificationDate(DateTime date) => '${_monthNames[date.month - 1].substring(0, 1)}${_monthNames[date.month - 1].substring(1).toLowerCase()} ${date.day}, ${date.year}';

String formatNotificationTime(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

/// True when a notification has somewhere concrete to take the user —
/// decides where tapping its detail dialog lands.
bool notificationHasTarget(NotificationItem n) =>
    n.relatedAppointmentId != null || n.relatedTransactionId != null;

/// Navigates to whatever this notification is about: an appointment (pushes
/// Appointments and opens that appointment's detail dialog) or a wallet
/// transaction (pushes Transaction History and opens that transaction's
/// detail dialog). Uses `context` after a short delay so the target screen's
/// push transition finishes before the follow-up dialog appears on top of it.
void _navigateForNotification(BuildContext context, NotificationItem n) {
  final repository = PatientRepository();
  if (n.relatedAppointmentId != null) {
    Appointment? appointment;
    for (final a in repository.appointments) {
      if (a.id == n.relatedAppointmentId) appointment = a;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AppointmentsScreen()));
    if (appointment != null) {
      final found = appointment;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (context.mounted) showAppointmentDetailSheet(context, found);
      });
    }
  } else if (n.relatedTransactionId != null) {
    WalletTransaction? txn;
    for (final t in repository.transactions) {
      if (t.id == n.relatedTransactionId) txn = t;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionHistoryScreen()));
    if (txn != null) {
      final found = txn;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (context.mounted) showTransactionDetailSheet(context, found);
      });
    }
  }
}

/// Compact floating dialog with a notification's full detail — used from the
/// home dropdown, the "See All" list, and the standalone Notifications screen.
/// The whole dialog is always tappable: it opens whatever the notification is
/// about (an appointment or a wallet transaction) and otherwise just dismisses,
/// so there is no need for a "tap to view" hint.
void showNotificationDetailDialog(BuildContext context, NotificationItem n) {
  final hasTarget = notificationHasTarget(n);
  showAppDialog(
    context,
    maxHeightFactor: 0.6,
    builder: (dialogContext) => InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () {
        Navigator.pop(dialogContext);
        if (hasTarget) _navigateForNotification(context, n);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: notificationColor(n).withOpacity(0.14), shape: BoxShape.circle),
                  child: Icon(notificationIcon(n), color: notificationColor(n), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    n.title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ),
                const AppDialogCloseButton(),
              ],
            ),
            const SizedBox(height: 16),
            Text(n.body, style: TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4)),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(CupertinoIcons.clock, size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  '${formatNotificationDate(n.createdAt)} • ${formatNotificationTime(n.createdAt)}',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class HomeTab extends StatefulWidget {
  final ValueChanged<int> onNavigateToTab;

  const HomeTab({super.key, required this.onNavigateToTab});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final PatientRepository _repository = PatientRepository();
  final LayerLink _bellLink = LayerLink();
  OverlayEntry? _notificationOverlay;

  @override
  void dispose() {
    _notificationOverlay?.remove();
    super.dispose();
  }

  BoxDecoration get _flatCardDecoration => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.10),
            blurRadius: 26,
            offset: const Offset(0, 12),
            spreadRadius: -8,
          ),
        ],
      );

  void _toggleNotifications() {
    if (_notificationOverlay != null) {
      _closeNotifications();
    } else {
      _openNotifications();
    }
  }

  void _openNotifications() {
    final overlay = Overlay.of(context);
    _notificationOverlay = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeNotifications,
              child: Container(color: Colors.transparent),
            ),
          ),
          CompositedTransformFollower(
            link: _bellLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 10),
            child: _NotificationDropdown(
              repository: _repository,
              onSeeAll: () {
                _closeNotifications();
                Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
              },
              onNotificationTap: (n) {
                _closeNotifications();
                _repository.markNotificationRead(n.id);
                showNotificationDetailDialog(context, n);
              },
            ),
          ),
        ],
      ),
    );
    overlay.insert(_notificationOverlay!);
    setState(() {});
  }

  void _closeNotifications() {
    _notificationOverlay?.remove();
    _notificationOverlay = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([_repository, ThemeController()]),
          builder: (context, _) {
            final appointment = _repository.nextUpcomingAppointment;
            final recentTransactions = _repository.transactions.take(3).toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 104),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildNextAppointmentCard(appointment),
                  const SizedBox(height: 16),
                  _buildWalletCard(),
                  const SizedBox(height: 20),
                  Text(
                    'Quick Actions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActions(),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Activity',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const TransactionHistoryScreen()),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            children: [
                              Text(
                                'See All',
                                style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 2),
                              Icon(CupertinoIcons.chevron_right, color: AppColors.primary, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildRecentActivityCard(recentTransactions),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome back,', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  _repository.patient.firstName,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 6),
                const Text('👋', style: TextStyle(fontSize: 20)),
              ],
            ),
          ],
        ),
        CompositedTransformTarget(
          link: _bellLink,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleNotifications,
              customBorder: const CircleBorder(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _notificationOverlay != null ? AppColors.primary.withOpacity(0.1) : AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(
                      _notificationOverlay != null ? CupertinoIcons.bell_fill : CupertinoIcons.bell,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  if (_repository.unreadNotificationCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        child: Text(
                          '${_repository.unreadNotificationCount}',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNextAppointmentCard(Appointment? appointment) {
    if (appointment == null) {
      return InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookAppointmentScreen())),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: _flatCardDecoration,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(CupertinoIcons.calendar_badge_plus, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No upcoming appointments',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text('Tap to book your next visit.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_right, color: AppColors.primary, size: 18),
            ],
          ),
        ),
      );
    }

    // Colored to match the wallet balance card treatment: solid teal
    // background with light/white text and icons for contrast.
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => showAppointmentDetailSheet(context, appointment),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF14B8A6),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.28),
              blurRadius: 26,
              offset: const Offset(0, 12),
              spreadRadius: -8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('NEXT APPOINTMENT',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.white70, letterSpacing: 0.6)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel(appointment.status),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _formatDateHeading(appointment.date),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              appointment.serviceName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(CupertinoIcons.clock, size: 14, color: Colors.white70),
                const SizedBox(width: 4),
                Text(appointment.timeSlot, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(width: 14),
                const Icon(CupertinoIcons.person, size: 14, color: Colors.white70),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    appointment.doctorName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => widget.onNavigateToTab(2),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _flatCardDecoration,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(CupertinoIcons.creditcard, color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Text('Wallet Balance',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                  ],
                ),
                Icon(CupertinoIcons.chevron_right, color: AppColors.primary, size: 18),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '₱ ${_repository.walletBalance.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text('Available Balance', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
                  child: Icon(CupertinoIcons.creditcard_fill, color: AppColors.primary, size: 24),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = <_QuickAction>[
      _QuickAction(
        icon: CupertinoIcons.calendar,
        label: 'Book\nAppointment',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookAppointmentScreen())),
      ),
      _QuickAction(icon: CupertinoIcons.money_dollar_circle, label: 'Billing', onTap: () => widget.onNavigateToTab(2)),
      _QuickAction(icon: CupertinoIcons.folder, label: 'My\nRecords', onTap: () => widget.onNavigateToTab(3)),
    ];

    return Row(
      children: [
        for (int i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: actions[i]),
        ],
      ],
    );
  }

  Widget _buildRecentActivityCard(List<WalletTransaction> transactions) {
    if (transactions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Text('No recent activity yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (int i = 0; i < transactions.length; i++) ...[
            if (i > 0) const Divider(height: 20),
            InkWell(
              onTap: () => showTransactionDetailSheet(
                context,
                transactions[i],
                onTapNavigate: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TransactionHistoryScreen()),
                ),
              ),
              child: _ActivityRow(transaction: transactions[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// The semicircle "punch" at each end of the ticket divider. Its color
/// matches the page background so it reads as a cutout in the card edge.
class _NotificationDropdown extends StatelessWidget {
  final PatientRepository repository;
  final VoidCallback onSeeAll;
  final ValueChanged<NotificationItem> onNotificationTap;

  const _NotificationDropdown({required this.repository, required this.onSeeAll, required this.onNotificationTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 310,
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 28, offset: const Offset(0, 12)),
          ],
        ),
        child: ListenableBuilder(
          listenable: repository,
          builder: (context, _) {
            final notifications = repository.notifications;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 16, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Notifications',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
                      if (repository.unreadNotificationCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${repository.unreadNotificationCount} new',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppColors.border),
                if (notifications.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Text('No notifications yet.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                      itemBuilder: (context, index) {
                        final n = notifications[index];
                        return InkWell(
                          onTap: () => onNotificationTap(n),
                          child: Container(
                            color: n.isRead ? Colors.transparent : AppColors.primary.withOpacity(0.05),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: notificationColor(n).withOpacity(0.14),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(notificationIcon(n), color: notificationColor(n), size: 16),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        n.title,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: n.isRead ? FontWeight.w600 : FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(n.body, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${formatNotificationDate(n.createdAt)} • ${formatNotificationTime(n.createdAt)}',
                                        style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!n.isRead)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4, left: 4),
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                Divider(height: 1, color: AppColors.border),
                InkWell(
                  onTap: onSeeAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('See All', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        Icon(CupertinoIcons.chevron_right, color: AppColors.primary, size: 14),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 8),
            SizedBox(
              height: 28,
              child: Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final WalletTransaction transaction;

  const _ActivityRow({required this.transaction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(transaction.icon, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(transaction.title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(
                '${transaction.subtitle} • ${transaction.dateTime.month}/${transaction.dateTime.day}',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Text(
          '${transaction.isCredit ? '+' : '-'} ₱${transaction.amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: transaction.isCredit ? AppColors.success : AppColors.error,
          ),
        ),
      ],
    );
  }
}
