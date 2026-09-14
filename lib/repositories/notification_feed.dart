import '../app/messages.dart';
import '../models/appointment.dart';
import '../models/notification.dart';
import '../models/payment.dart';
import '../models/treatment.dart';
import '../models/wallet_transaction.dart';
import '../services/push_notification_service.dart';

/// What the patient has done with one notice.
///
/// For a shared notice this mirrors `notification_state`; for an app-only
/// notice it is kept on the device.
class NotificationState {
  final DateTime? readAt;
  final DateTime? dismissedAt;

  const NotificationState({this.readAt, this.dismissedAt});

  bool get isRead => readAt != null;
  bool get isDismissed => dismissedAt != null;
}

/// One notice in the feed and the mute category it answers to.
class FeedNotice {
  final NotificationItem item;
  final PushChannel channel;

  const FeedNotice(this.item, this.channel);
}

/// The patient's notification feed, assembled from the records themselves.
///
/// Messages are not part of it. The website keeps two independent counters —
/// the bell for this feed, the chat icon for `patient_messages` rows the
/// clinic sent that have no `read_at` — and never merges them, so neither does
/// the app.
///
/// **Shared with the website** — keys built character for character the way
/// the website builds them, read state in `notification_state`, written only
/// through `notif_mark_read` / `notif_dismiss`:
///   `booked|<appointment id>`       `booked_by` is exactly `'clinic'`
///   `confirmed|<appointment_date>|<appointment_time>`
///   `awaiting|<appointment id>`     pending and not booked by the clinic
///   `reminder|<appointment_date>|<appointment_time>`   0-2 calendar days out
///   `rcpt|<payment_receipts.id>`
///   `plan|<treatment_plans.id>|<updated_at ?? created_at>`
/// The four appointment notices are built only from rows whose status is
/// exactly `Confirmed` or `Pending` — the website's own feed query filters on
/// that set, so a row leaving it takes all its notices with it.
///
/// **App-only** — `local:<kind>:<id>` for a cancelled or completed visit, a
/// payment due and wallet movements. The website has no such notices, so their
/// read state stays on the device and never reaches `notification_state`.
class NotificationFeed {
  NotificationFeed._();

  /// Older activity is history, not news.
  static const Duration window = Duration(days: 90);
  static const int maxItems = 100;

  /// The website's plans query: newest 10 by `updated_at`.
  static const int maxPlans = 10;

  static const List<String> _sharedPrefixes = [
    'booked|',
    'confirmed|',
    'awaiting|',
    'reminder|',
    'rcpt|',
    'plan|',
  ];
  static const String _localPrefix = 'local:';

  /// A notice the website also shows, synced through `notification_state`.
  static bool isShared(String id) => _sharedPrefixes.any(id.startsWith);

  /// An app-only notice, read state kept on the device.
  static bool isLocal(String id) => id.startsWith(_localPrefix);

  /// True for any notice built here rather than read from `notifications`.
  static bool isDerived(String id) => isShared(id) || isLocal(id);

  static List<FeedNotice> build({
    List<Appointment> appointments = const [],
    List<Payment> billing = const [],
    List<WalletTransaction> transactions = const [],
    List<TreatmentPlanSummary> plans = const [],
    Map<String, NotificationState> state = const {},
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final cutoff = clock.subtract(window);
    final notices = <FeedNotice>[];
    final seen = <String>{};

    void add({
      required String key,
      required String title,
      required String body,
      required DateTime at,
      required PushChannel channel,
      bool readByDefault = false,
      String? appointmentId,
      String? transactionId,
    }) {
      // Keys without a row id (confirmed, reminder) can repeat across two
      // bookings in one slot; the website shows one notice, so does the app.
      if (!seen.add(key)) return;
      if (at.isBefore(cutoff)) return;
      final saved = state[key];
      if (saved?.isDismissed ?? false) return;
      notices.add(FeedNotice(
        NotificationItem(
          id: key,
          title: title,
          body: body,
          // Never in the future: a reminder dated ahead would sit above news.
          createdAt: at.isAfter(clock) ? clock : at,
          isRead: (saved?.isRead ?? false) || readByDefault,
          readAt: saved?.readAt,
          relatedAppointmentId: appointmentId,
          relatedTransactionId: transactionId,
        ),
        channel,
      ));
    }

    final today = DateTime.utc(clock.year, clock.month, clock.day);

    String whenOf(Appointment a) => '${_date(a.date)} at ${a.timeSlot}';
    String withDoctorOf(Appointment a) {
      final doctor = a.doctorName.trim();
      return doctor.isEmpty || doctor == kDoctorAssignedUnnamed ? '' : ' with $doctor';
    }

    // --- Shared: the website's feed query, `.in('status', ['Confirmed','Pending'])`.
    final open = appointments.where((a) => a.rawStatus == 'Confirmed' || a.rawStatus == 'Pending');
    for (final a in open) {
      final service = a.serviceName;
      final when = whenOf(a);
      final withDoctor = withDoctorOf(a);
      final byClinic = !a.isSelfBooked;

      if (byClinic) {
        add(
          key: 'booked|${a.id}',
          title: 'Appointment booked for you',
          body: 'The clinic booked $service on $when$withDoctor.',
          at: a.createdAt ?? a.startsAt,
          channel: PushChannel.statusUpdate,
          appointmentId: a.id,
        );
      }

      if (a.rawStatus == 'Confirmed') {
        add(
          key: 'confirmed|${a.rawDate}|${a.rawTime}',
          title: 'Appointment confirmed',
          body: '$service on $when$withDoctor is confirmed.',
          at: a.statusChangedAt ?? a.createdAt ?? a.startsAt,
          channel: PushChannel.statusUpdate,
          appointmentId: a.id,
        );
      } else if (!byClinic) {
        add(
          key: 'awaiting|${a.id}',
          title: 'Awaiting confirmation',
          body: '$service on $when is waiting for the clinic to confirm.',
          at: a.createdAt ?? a.startsAt,
          channel: PushChannel.statusUpdate,
          appointmentId: a.id,
        );
      }

      // Calendar days only, no time of day: a visit earlier today still counts.
      final visitDay = DateTime.utc(a.date.year, a.date.month, a.date.day);
      final daysOut = (visitDay.difference(today).inHours / 24).round();
      if (daysOut >= 0 && daysOut <= 2) {
        final label = daysOut == 0 ? 'today' : (daysOut == 1 ? 'tomorrow' : 'in 2 days');
        add(
          key: 'reminder|${a.rawDate}|${a.rawTime}',
          title: 'Appointment reminder',
          body: '$service is $label, ${a.timeSlot}$withDoctor.',
          at: a.startsAt.subtract(const Duration(days: 2)),
          channel: PushChannel.reminder,
          appointmentId: a.id,
        );
      }
    }

    // --- Shared: payment received.
    for (final p in billing) {
      final receiptId = p.receiptId ?? '';
      if (!p.isPaid || receiptId.isEmpty) continue;
      final method = (p.paymentMethod ?? '').trim();
      add(
        key: 'rcpt|$receiptId',
        title: 'Payment received',
        body: '${p.procedureName} — ${formatPeso(p.amount)} paid'
            '${method.isEmpty ? '' : ' via $method'}.',
        at: p.receiptIssuedAt ?? p.billedOn,
        channel: PushChannel.payment,
      );
    }

    // --- Shared: the website's plans query, no status filter, newest 10 by
    // `updated_at desc` (Postgres puts a null `updated_at` first in that order).
    final recentPlans = [...plans]..sort((a, b) {
        final au = a.updatedAt;
        final bu = b.updatedAt;
        if (au == null && bu == null) return 0;
        if (au == null) return -1;
        if (bu == null) return 1;
        return bu.compareTo(au);
      });
    for (final plan in recentPlans.take(maxPlans)) {
      if (plan.id.isEmpty || plan.stamp.isEmpty) continue;
      final name = plan.title.trim().isEmpty ? 'Your treatment plan' : plan.title.trim();
      final String title;
      final String body;
      if (plan.status == 'completed') {
        title = 'Treatment plan completed';
        body = '$name is complete.';
      } else if (plan.wasUpdated) {
        title = 'Treatment plan updated';
        body = '$name was updated by the clinic.';
      } else {
        title = 'New treatment plan';
        body = 'The clinic added $name to your records.';
      }
      add(
        key: 'plan|${plan.id}|${plan.stamp}',
        title: title,
        body: body,
        at: plan.changedAt,
        channel: PushChannel.statusUpdate,
      );
    }

    // --- App-only: the website has no such notices.
    for (final a in appointments) {
      if (a.status == AppointmentStatus.cancelled) {
        final reason = (a.cancellationReason ?? '').trim();
        add(
          key: '${_localPrefix}cancelled:${a.id}',
          title: 'Appointment cancelled',
          body: '${a.serviceName} on ${whenOf(a)} was cancelled.'
              '${reason.isEmpty ? '' : ' Reason: $reason'}',
          at: a.statusChangedAt ?? a.createdAt ?? a.startsAt,
          channel: PushChannel.statusUpdate,
          appointmentId: a.id,
        );
      } else if (a.status == AppointmentStatus.completed) {
        add(
          key: '${_localPrefix}completed:${a.id}',
          title: 'Appointment completed',
          body: 'Your ${a.serviceName} visit on ${_date(a.date)} is complete.',
          at: a.statusChangedAt ?? a.startsAt,
          channel: PushChannel.statusUpdate,
          appointmentId: a.id,
        );
      }
    }

    for (final p in billing) {
      if (p.isPaid) continue;
      add(
        key: '${_localPrefix}due:${p.id}',
        title: 'Payment due',
        body: '${p.procedureName} — ${formatPeso(p.amount)} is on your statement.',
        at: p.billedOn,
        channel: PushChannel.payment,
      );
    }

    for (final t in transactions) {
      final amount = formatPeso(t.amount);
      if (t.isCredit) {
        add(
          key: '${_localPrefix}topup:${t.id}',
          title: 'Wallet top-up received',
          body: '$amount was added to your wallet${t.method.isEmpty ? '' : ' via ${t.method}'}.',
          at: t.dateTime,
          channel: PushChannel.payment,
          transactionId: t.id,
        );
      } else {
        add(
          key: '${_localPrefix}walletpay:${t.id}',
          title: 'Wallet payment',
          body: '$amount paid from your wallet for ${t.title}.',
          at: t.dateTime,
          channel: PushChannel.payment,
          // Spent by the patient at checkout: a record, not news.
          readByDefault: true,
          transactionId: t.id,
        );
      }
    }

    notices.sort((a, b) => b.item.createdAt.compareTo(a.item.createdAt));
    return notices.length > maxItems ? notices.sublist(0, maxItems) : notices;
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
}
