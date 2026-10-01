import 'package:flutter/material.dart';

import '../../models/appointment.dart';
import '../../models/notification.dart';
import '../../repositories/patient_repository.dart';
import '../appointments/appointment_details_screen.dart';
import '../records/dental_records_screen.dart';
import '../wallet/pay_screens.dart';
import '../wallet/transaction_history_screen.dart';
import 'notifications_screen.dart';

/// What tapping a notice does — the website's `_notifClickAttr` and
/// `openPatientNotifTarget`.
///
/// The notice is marked read first, locally at once and then on the account,
/// so the badge drops before anything opens. Then it opens what it is about:
/// the exact appointment by id (a cancelled one included), Billing &
/// Receipts, or the Treatment Plan. A notice with nowhere to go opens the
/// Notifications list, as on the website.
///
/// [onNotificationsScreen] is true when the tap came from that list, so the
/// fallback does not push a second copy of it.
Future<void> openNotification(
  BuildContext context,
  NotificationItem n, {
  bool onNotificationsScreen = false,
}) async {
  final repository = PatientRepository();
  if (!n.isRead) {
    // Not awaited: the write carries on while the target opens.
    repository.markNotificationRead(n.id);
  }

  final target = n.target;
  if (target == null) {
    if (!onNotificationsScreen) _openList(context);
    return;
  }

  switch (target.type) {
    case NotificationTargetType.appointment:
      Appointment? cached;
      for (final a in repository.appointments) {
        if (a.id == target.id) cached = a;
      }
      // The details page reads the row fresh by id, so a booking that has
      // since been cancelled, or has dropped out of the cached list, still
      // opens; it says so itself if the booking no longer exists.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              AppointmentDetailsPage(appointmentId: target.id, initial: cached),
        ),
      );
    case NotificationTargetType.billing:
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const TransactionHistoryScreen(initialTabIndex: 1),
        ),
      );
    case NotificationTargetType.plan:
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const DentalRecordsScreen(initialTabIndex: 1),
        ),
      );
    case NotificationTargetType.visitPayment:
      // Opens the request itself; one already paid or withdrawn says so.
      openVisitRequest(context, target.id);
    case NotificationTargetType.slotOffer:
      _unavailable(
        context,
        'Earlier-time offers can only be accepted on the M&B Dental website for now.',
        onNotificationsScreen: onNotificationsScreen,
      );
  }
}

void _openList(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
}

/// The target cannot be opened here. Says so plainly and, when the patient is
/// not already on it, offers the Notifications list as the way on.
void _unavailable(
  BuildContext context,
  String message, {
  required bool onNotificationsScreen,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    if (!onNotificationsScreen) _openList(context);
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: onNotificationsScreen
            ? null
            : SnackBarAction(
                label: 'Notifications',
                onPressed: () => _openList(context),
              ),
      ),
    );
}
