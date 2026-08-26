import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/models/notification.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/screens/appointments/book_appointment_screen.dart';
import 'package:mb_dental_app/screens/dashboard/notifications_screen.dart';
import 'package:mb_dental_app/screens/wallet/transaction_history_screen.dart';
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
          listenable: _repository,
          builder: (context, _) {
            final appointment = _repository.nextUpcomingAppointment;
            final recentTransactions = _repository.transactions.take(3).toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
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
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const TransactionHistoryScreen()),
                        ),
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
          child: GestureDetector(
            onTap: _toggleNotifications,
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
      onTap: () {
        widget.onNavigateToTab(1);
        showAppointmentDetailSheet(context, appointment);
      },
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.primary,
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
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Next Appointment',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
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
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
                        child: const Icon(CupertinoIcons.sparkles, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDateHeading(appointment.date),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              appointment.serviceName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(CupertinoIcons.clock, size: 13, color: Colors.white70),
                                const SizedBox(width: 4),
                                Text(appointment.timeSlot,
                                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(CupertinoIcons.person, size: 13, color: Colors.white70),
                                const SizedBox(width: 4),
                                Text(appointment.doctorName,
                                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildTicketDivider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('View full details',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  Icon(CupertinoIcons.chevron_right, color: Colors.white, size: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A boarding-pass-style tear line: a dashed rule with two semicircle
  /// notches punched into the card's edges, colored to match the page
  /// background so they read as cutouts.
  Widget _buildTicketDivider() {
    return SizedBox(
      height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: List.generate(24, (i) {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 1.5,
                    color: Colors.white.withOpacity(0.35),
                  ),
                );
              }),
            ),
          ),
          const Positioned(left: -10, child: _TicketNotch()),
          const Positioned(right: -10, child: _TicketNotch()),
        ],
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
      _QuickAction(icon: CupertinoIcons.folder, label: 'My\nRecords', onTap: () => widget.onNavigateToTab(3)),
      _QuickAction(icon: CupertinoIcons.creditcard, label: 'Wallet', onTap: () => widget.onNavigateToTab(2)),
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
              onTap: () => showTransactionDetailSheet(context, transactions[i]),
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
class _TicketNotch extends StatelessWidget {
  const _TicketNotch();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(color: AppColors.background, shape: BoxShape.circle),
    );
  }
}

class _NotificationDropdown extends StatelessWidget {
  final PatientRepository repository;
  final VoidCallback onSeeAll;

  const _NotificationDropdown({required this.repository, required this.onSeeAll});

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
                          onTap: () => repository.markNotificationRead(n.id),
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
