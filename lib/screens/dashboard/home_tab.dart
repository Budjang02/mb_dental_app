import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/data/clinic_catalog.dart';
import 'package:mb_dental_app/models/dental_service.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/models/notification.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/screens/appointments/appointments_screen.dart';
import 'package:mb_dental_app/screens/appointments/book_appointment_screen.dart';
import 'package:mb_dental_app/screens/chat/chat_screen.dart';
import 'package:mb_dental_app/screens/dashboard/notifications_screen.dart';
import 'package:mb_dental_app/screens/wallet/transaction_history_screen.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';
import 'package:mb_dental_app/widgets/appointment_detail_sheet.dart';
import 'package:mb_dental_app/widgets/transaction_detail_sheet.dart';

const List<String> _monthNames = [
  'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
  'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
];

const List<String> _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

/// "Wednesday, September 2, 2026" — the full heading used on the next
/// appointment card.
String _formatFullDate(DateTime date) {
  final month = _monthNames[date.month - 1];
  final titleCased = '${month[0]}${month.substring(1).toLowerCase()}';
  return '${_weekdayNames[date.weekday - 1]}, $titleCased ${date.day}, ${date.year}';
}

/// Three-letter month for the date badge, e.g. "SEP".
String _shortMonth(DateTime date) => _monthNames[date.month - 1].substring(0, 3);

/// The website's Font Awesome (solid) icon for each notice type. The six keys
/// shared with the website use its own icons; app-only notices, which the
/// website does not have, and `notifications` rows get the nearest equivalent.
FaIconData notificationIconFor(NotificationItem n) {
  final id = n.id;
  if (id.startsWith('booked|')) return FontAwesomeIcons.calendarPlus;
  if (id.startsWith('confirmed|')) return FontAwesomeIcons.calendarCheck;
  if (id.startsWith('awaiting|')) return FontAwesomeIcons.hourglassHalf;
  if (id.startsWith('reminder|')) return FontAwesomeIcons.clock;
  if (id.startsWith('rcpt|')) return FontAwesomeIcons.receipt;
  if (id.startsWith('plan|')) return FontAwesomeIcons.listCheck;
  if (id.startsWith('local:cancelled:')) return FontAwesomeIcons.calendarXmark;
  if (id.startsWith('local:completed:')) return FontAwesomeIcons.circleCheck;
  if (id.startsWith('local:due:')) return FontAwesomeIcons.fileInvoiceDollar;
  if (id.startsWith('local:topup:') || id.startsWith('local:walletpay:')) {
    return FontAwesomeIcons.wallet;
  }
  return FontAwesomeIcons.bell;
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
    // Appointments lists every booking on one page, so there is no tab to
    // pick here — push the list and open this appointment's detail on top.
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppointmentsScreen()),
    );
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

                Expanded(
                  child: Text(
                    n.title,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ),
                const AppDialogCloseButton(),
              ],
            ),
            const SizedBox(height: 16),
            Text(n.body, style: TextStyle(fontSize: 15, color: AppColors.textPrimary, height: 1.45)),
            const SizedBox(height: 16),
            Row(
              children: [
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
                      // Flexible so a large system font size shrinks the
                      // heading instead of overflowing the row.
                      Flexible(
                        child: Text(
                          'Recent Transaction',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
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
                  _buildRecentTransactionCard(recentTransactions),
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
        // Expanded so a long name yields to the two action buttons beside it
        // rather than pushing the row past the screen edge.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome back,', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _repository.patient.firstName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ],
          ),
        ),
        // Messages and notifications share the top-right corner.
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())),
            customBorder: const CircleBorder(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: Center(
                      child: FaIcon(FontAwesomeIcons.commentDots, color: AppColors.primary, size: 19),
                    ),
                  ),
                ),
                // Counts only what the clinic sent and the patient has not
                // opened — the patient's own messages are never unread.
                if (_repository.unreadMessageCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      child: Text(
                        '${_repository.unreadMessageCount}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
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
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: Center(
                        child: FaIcon(FontAwesomeIcons.bell, color: AppColors.primary, size: 19),
                      ),
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

  /// The deep gradient panel (dark navy -> forest green) the next-appointment
  /// card is drawn on. Shared with the empty state so an account with nothing
  /// booked still gets the same block of colour in the same place, rather than
  /// the page rearranging itself around a flat placeholder.
  BoxDecoration get _nextAppointmentDecoration => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          // Light mode gets a brighter teal-to-emerald wash so the card
          // lifts off the pale page instead of sitting on it as a dark slab.
          colors: ThemeController().isDark
              ? const [Color(0xFF0B1D2A), Color(0xFF0E4A46), Color(0xFF12604A)]
              : const [Color(0xFF11796D), Color(0xFF19A38D), Color(0xFF33B384)],
          stops: const [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.28),
            blurRadius: 26,
            offset: const Offset(0, 12),
            spreadRadius: -8,
          ),
        ],
      );

  Widget _buildNextAppointmentCard(Appointment? appointment) {
    if (appointment == null) {
      return InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookAppointmentScreen())),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: _nextAppointmentDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NEXT APPOINTMENT',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: Colors.white70,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                    ),
                    child: const Icon(CupertinoIcons.calendar_badge_plus,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No upcoming appointments',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Book one and it will show up here.',
                          style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const Icon(CupertinoIcons.chevron_right, color: Colors.white70, size: 18),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // The booked card: a date badge on the left, the visit details beside it.
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => showAppointmentDetailSheet(context, appointment),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: _nextAppointmentDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'NEXT APPOINTMENT',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: Colors.white70,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                _buildStatusPill(appointment.status),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDateBadge(appointment.date),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatFullDate(appointment.date),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        appointment.timeSlot.isEmpty ? 'Time to be confirmed' : appointment.timeSlot,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
                      ),
                      // The start time alone does not say when the patient
                      // is free again, so the block's end and length ride with
                      // it. Skipped only for a legacy slot label that cannot
                      // be parsed back to a start minute.
                      if (appointment.endMinuteOfDay != null) ...[
                        const SizedBox(height: 4),
                        _buildDetailLine(
                          'Until ${formatMinuteOfDay(appointment.endMinuteOfDay!)}'
                          ' · ${formatDuration(appointment.durationMinutes)}',
                        ),
                      ],
                      const SizedBox(height: 12),
                      // The website prints the doctor's `full_name`, and
                      // "your doctor" when there is none.
                      _buildDetailLine(
                        appointment.doctorName.trim().isEmpty ||
                                appointment.doctorName.trim() == kDoctorAssignedUnnamed
                            ? 'your doctor'
                            : appointment.doctorName.trim(),
                      ),

                      const SizedBox(height: 6),
                      _buildDetailLine(appointment.serviceName.trim().isEmpty ? 'Appointment' : appointment.serviceName),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The "SEP / 2" tile on the left of the next appointment card.
  Widget _buildDateBadge(DateTime date) {
    return Container(
      width: 62,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        children: [
          Text(
            _shortMonth(date),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${date.day}',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white, height: 1.1),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(AppointmentStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFD9F5E3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        statusLabel(status),
        style: const TextStyle(color: Color(0xFF106B45), fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildDetailLine(String text) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, color: Colors.white),
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
                Text('Wallet Balance',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
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
    // The website's four quick actions, in its order, with its icons.
    final actions = <_QuickAction>[
      _QuickAction(
        icon: FontAwesomeIcons.calendarPlus,
        label: 'Book\nAppointment',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookAppointmentScreen())),
      ),
      _QuickAction(
        icon: FontAwesomeIcons.plus,
        label: 'Add\nMoney',
        onTap: () => widget.onNavigateToTab(2),
      ),
      _QuickAction(
        icon: FontAwesomeIcons.fileMedical,
        label: 'My\nRecords',
        onTap: () => widget.onNavigateToTab(3),
      ),
      _QuickAction(
        icon: FontAwesomeIcons.commentDots,
        label: 'Message\nClinic',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())),
      ),
    ];

    return Row(
      children: [
        for (int i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: actions[i]),
        ],
      ],
    );
  }

  Widget _buildRecentTransactionCard(List<WalletTransaction> transactions) {
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
          child: Text('No recent transactions yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
      // Deliberately compact: this is a peek at what is waiting, not the
      // notification list. Each row carries the message and nothing else —
      // the title, timestamp and everything around them live one tap away,
      // in the detail dialog and on the "See All" page.
      child: Container(
        width: 300,
        constraints: const BoxConstraints(maxHeight: 380),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 24, offset: const Offset(0, 10)),
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
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 7),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Notifications',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
                      if (repository.unreadNotificationCount > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${repository.unreadNotificationCount} new',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Tooltip(
                              message: 'Mark all as read',
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: repository.markAllNotificationsRead,
                                child: Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: Icon(Icons.done_all_rounded, size: 16, color: AppColors.primary),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppColors.border),
                if (notifications.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 26),
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
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2, right: 10),
                                  child: FaIcon(notificationIconFor(n), size: 15, color: AppColors.primary),
                                ),
                                Expanded(
                                  child: Text(
                                    n.body,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      height: 1.35,
                                      fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w600,
                                      color: n.isRead ? AppColors.textSecondary : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (!n.isRead)
                                  Container(
                                    margin: const EdgeInsets.only(top: 9, left: 7),
                                    width: 6,
                                    height: 6,
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
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('See All', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
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
  final FaIconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 8),
            SizedBox(
              height: 28,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  textAlign: TextAlign.center,
                ),
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
    // No leading icon: every row on this card carried the same generic badge,
    // so it added a column of visual noise without telling the rows apart.
    // The title, subtitle and signed amount already do that.
    return Row(
      children: [
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
