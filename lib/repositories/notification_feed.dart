import '../app/messages.dart';
import '../models/appointment.dart';
import '../models/notification.dart';
import '../models/treatment.dart';
import '../services/push_notification_service.dart';

/// What the patient has done with one notice, from `notification_state`.
class NotificationState {
  final DateTime? readAt;
  final DateTime? dismissedAt;

  const NotificationState({this.readAt, this.dismissedAt});

  bool get isRead => readAt != null;
  bool get isDismissed => dismissedAt != null;
}

/// Settings → Notifications, shared with the website through
/// `notification_prefs`: the master switch and the three categories. They
/// decide what is in the feed, so they decide the bell's count.
class NotificationPrefs {
  final bool enabled;
  final bool appointment;
  final bool plan;
  final bool billing;

  const NotificationPrefs({
    this.enabled = true,
    this.appointment = true,
    this.plan = true,
    this.billing = true,
  });

  bool allows(String category) => switch (category) {
    'plan' => plan,
    'billing' => billing,
    _ => appointment,
  };

  NotificationPrefs copyWith({
    bool? enabled,
    bool? appointment,
    bool? plan,
    bool? billing,
  }) => NotificationPrefs(
    enabled: enabled ?? this.enabled,
    appointment: appointment ?? this.appointment,
    plan: plan ?? this.plan,
    billing: billing ?? this.billing,
  );

  @override
  bool operator ==(Object other) =>
      other is NotificationPrefs &&
      other.enabled == enabled &&
      other.appointment == appointment &&
      other.plan == plan &&
      other.billing == billing;

  @override
  int get hashCode => Object.hash(enabled, appointment, plan, billing);
}

/// What the bell needs from the server besides the record: the addressed
/// rows, the `<event>|<entity id>` pairs that retire derived duplicates, and
/// the newest receipts.
class NotificationSources {
  final List<NotificationItem> addressed;
  final Set<String> covered;
  final List<ReceiptNotice> receipts;

  const NotificationSources({
    this.addressed = const [],
    this.covered = const {},
    this.receipts = const [],
  });
}

/// A `payment_receipts` row, as the website's receipt notice reads it.
class ReceiptNotice {
  final String id;
  final String referenceNo;
  final String procedureName;
  final double amountDue;
  final String paymentMethod;
  final DateTime issuedAt;

  const ReceiptNotice({
    required this.id,
    required this.issuedAt,
    this.referenceNo = '',
    this.procedureName = '',
    this.amountDue = 0,
    this.paymentMethod = '',
  });
}

/// The patient's bell, built by the same rules as the website's so both show
/// the same notices and the same unread count for one account.
///
/// **Addressed** — `notifications` rows, key `db|<uuid>`: the newest
/// [addressedLimit] plus every unread row (see `PatientApi.fetchNotifications`,
/// and `loadDbNotifs` in js/notif-feed.js).
///
/// **Derived** — built character for character the way js/render-patient.js,
/// js/patient-billing.js and js/patient-plan.js build them:
///   `booked|<appointment id>`       `booked_by` is exactly `'clinic'`
///   `confirmed|<appointment_date>|<appointment_time>`
///   `awaiting|<appointment id>`     status `Pending`, not booked by the clinic
///   `reminder|<appointment_date>|<appointment_time>`   0-2 Manila days out
///   `rcpt|<payment_receipts.id>`
///   `plan|<treatment_plans.id>|<updated_at ?? created_at>`
/// from at most [maxAppointments] upcoming appointments whose status is
/// `Confirmed`, `Pending` or `Pending Payment`, the newest [maxReceipts]
/// receipts and the newest [maxPlans] plans.
///
/// A derived notice an addressed row already says is dropped (see
/// [coverEvents]), so one confirmation is one entry, while genuinely separate
/// events — two reschedules — stay two.
///
/// Read state is `notification_state`, plus `read_at` on an addressed row.
/// Dismissed notices and switched-off categories are left out here, so the
/// list and the count are always the same set.
class NotificationFeed {
  NotificationFeed._();

  static const int addressedLimit = 30;
  static const int maxAppointments = 20;
  static const int maxReceipts = 10;
  static const int maxPlans = 10;

  /// Addressed events that restate a derived notice. Same list as
  /// `NOTIF_COVER_EVENTS` in js/notif-feed.js.
  static const List<String> coverEvents = [
    'appointment.confirmed',
    'appointment.booked_for_you',
    'billing.receipt',
  ];

  static const Set<String> _openStatuses = {
    'Confirmed',
    'Pending',
    'Pending Payment',
  };

  static List<NotificationItem> build({
    List<NotificationItem> addressed = const [],
    Set<String> covered = const {},
    List<Appointment> appointments = const [],
    List<ReceiptNotice> receipts = const [],
    List<TreatmentPlanSummary> plans = const [],
    Map<String, NotificationState> state = const {},
    NotificationPrefs prefs = const NotificationPrefs(),
    DateTime? now,
  }) {
    final derived = <(NotificationItem, String?)>[
      ..._fromAppointments(appointments, now ?? DateTime.now()),
      ..._fromReceipts(receipts),
      ..._fromPlans(plans),
    ];

    final byTime = [...addressed]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final all = <NotificationItem>[
      ...byTime,
      for (final (item, covers) in derived)
        if (covers == null || !covered.contains(covers)) item,
    ];

    final seen = <String>{};
    final out = <NotificationItem>[];
    for (final item in all) {
      if (!seen.add(item.id)) continue;
      final saved = state[item.id];
      if (saved?.isDismissed ?? false) continue;
      if (!prefs.allows(item.category)) continue;
      final read = item.isRead || (saved?.isRead ?? false);
      out.add(
        read == item.isRead
            ? item
            : item.copyWith(isRead: true, readAt: saved?.readAt ?? item.readAt),
      );
    }
    return out;
  }

  // --- Appointments: _buildNotifsFromAppts in js/render-patient.js. ---
  static List<(NotificationItem, String?)> _fromAppointments(
    List<Appointment> appointments,
    DateTime now,
  ) {
    final today = manilaDate(now);
    final open =
        appointments
            .where(
              (a) =>
                  _openStatuses.contains(a.rawStatus) &&
                  a.rawDate.compareTo(today) >= 0,
            )
            .toList()
          ..sort((a, b) {
            final byDate = a.rawDate.compareTo(b.rawDate);
            return byDate != 0 ? byDate : a.rawTime.compareTo(b.rawTime);
          });

    final items = <(int, NotificationItem, String?)>[];
    var order = 0;
    final todayDay = DateTime.parse(today);
    for (final a in open.take(maxAppointments)) {
      final day = DateTime.tryParse(a.rawDate);
      if (day == null) continue;
      final dayDiff = (day.difference(todayDay).inHours / 24).round();
      // Manila midnight of the visit day, as an instant, so the day heading is
      // the clinic's day whatever the phone's time zone.
      final visitDay = DateTime.utc(
        day.year,
        day.month,
        day.day,
      ).subtract(const Duration(hours: 8));
      final doctor = a.doctorName.trim();
      final doc = doctor.isEmpty || doctor == kDoctorAssignedUnnamed
          ? 'your doctor'
          : doctor;
      final proc = a.serviceName.trim().isEmpty
          ? 'your appointment'
          : a.serviceName.trim();
      final when = formatSchedule(a.rawDate, a.rawTime);
      final rel = dayDiff <= 0
          ? 'Today'
          : (dayDiff == 1 ? 'Tomorrow' : 'In $dayDiff days');
      final status = a.rawStatus.toLowerCase();
      final target = a.id.isEmpty
          ? null
          : NotificationTarget(NotificationTargetType.appointment, a.id);
      final byClinic = !a.isSelfBooked;

      void add(
        String key,
        String event,
        String title,
        String body,
        String? covers,
      ) {
        items.add((
          order++,
          NotificationItem(
            id: key,
            title: title,
            body: body,
            createdAt: visitDay,
            sortAt: visitDay,
            event: event,
            meta: rel,
            category: 'appointment',
            target: target,
          ),
          covers,
        ));
      }

      if (byClinic && a.id.isNotEmpty) {
        add(
          'booked|${a.id}',
          'appointment.booked_for_you',
          'The clinic booked an appointment for you',
          '$when — $doc',
          'appointment.booked_for_you|${a.id}',
        );
      }
      if (status == 'confirmed') {
        add(
          'confirmed|${a.rawDate}|${a.rawTime}',
          'appointment.confirmed',
          'Appointment Confirmed',
          '$when — $doc',
          a.id.isEmpty ? null : 'appointment.confirmed|${a.id}',
        );
      }
      if (status == 'pending' && !byClinic && a.id.isNotEmpty) {
        add(
          'awaiting|${a.id}',
          'appointment.pending',
          'Awaiting confirmation',
          '$when — the clinic will confirm this shortly',
          null,
        );
      }
      if (dayDiff >= 0 && dayDiff <= 2) {
        final relText = dayDiff == 0
            ? 'today'
            : (dayDiff == 1
                  ? 'tomorrow'
                  : 'on ${formatSchedule(a.rawDate, '')}');
        add(
          'reminder|${a.rawDate}|${a.rawTime}',
          'appointment.reminder',
          'Upcoming Appointment',
          'Reminder: $proc $relText',
          null,
        );
      }
    }
    // By visit day, keeping each appointment's own order (the website's sort
    // is stable; Dart's is not, hence the explicit tie-break).
    items.sort((x, y) {
      final byDay = x.$2.sortAt.compareTo(y.$2.sortAt);
      return byDay != 0 ? byDay : x.$1.compareTo(y.$1);
    });
    return [for (final (_, item, covers) in items) (item, covers)];
  }

  // --- Receipts: _receiptNotifs in js/patient-billing.js. ---
  static List<(NotificationItem, String?)> _fromReceipts(
    List<ReceiptNotice> receipts,
  ) {
    final newest = [...receipts]
      ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return [
      for (final r in newest.take(maxReceipts))
        (
          NotificationItem(
            id: 'rcpt|${r.id}',
            title: 'Payment received',
            body:
                '${r.procedureName.isEmpty ? 'Charge' : r.procedureName} — '
                '${formatPeso(r.amountDue)} (${r.paymentMethod.isEmpty ? '—' : r.paymentMethod})',
            createdAt: r.issuedAt,
            event: 'billing.paid',
            meta: r.referenceNo,
            category: 'billing',
            target: NotificationTarget(NotificationTargetType.billing, r.id),
          ),
          'billing.receipt|${r.id}',
        ),
    ];
  }

  // --- Plans: _planNotifs in js/patient-plan.js. Newest 10 by `updated_at`
  // desc, which in Postgres puts a null `updated_at` first. ---
  static List<(NotificationItem, String?)> _fromPlans(
    List<TreatmentPlanSummary> plans,
  ) {
    final recent = [...plans]
      ..sort((a, b) {
        final au = a.updatedAt;
        final bu = b.updatedAt;
        if (au == null && bu == null) return 0;
        if (au == null) return -1;
        if (bu == null) return 1;
        return bu.compareTo(au);
      });
    return [
      for (final plan in recent.take(maxPlans))
        if (plan.id.isNotEmpty && plan.stamp.isNotEmpty)
          (
            NotificationItem(
              id: 'plan|${plan.id}|${plan.stamp}',
              title: !plan.wasUpdated
                  ? 'New treatment plan'
                  : (plan.status.toLowerCase() == 'completed'
                        ? 'Treatment plan completed'
                        : 'Treatment plan updated'),
              body: plan.title.trim().isEmpty
                  ? 'Your dentist updated your treatment plan.'
                  : plan.title,
              createdAt: plan.changedAt,
              event: 'treatment_plan',
              meta: 'Treatment plan',
              category: 'plan',
              target: NotificationTarget(NotificationTargetType.plan, plan.id),
            ),
            null,
          ),
    ];
  }

  // --- Addressed rows: loadDbNotifs in js/notif-feed.js. ---

  /// The Settings category an addressed event is filed under (`_ndbCat`).
  static String categoryOf(String event) {
    if (event.startsWith('billing') ||
        event.startsWith('appointment.paid') ||
        event.startsWith('visit_payment')) {
      return 'billing';
    }
    if (event.startsWith('clinical')) return 'plan';
    return 'appointment';
  }

  /// Where an addressed row opens (`_ndbGo`). Null when it has nowhere to go.
  static NotificationTarget? targetOf({
    required String event,
    required String entity,
    required String entityId,
  }) {
    if (entityId.isEmpty) return null;
    if (event.startsWith('clinical.treatment_plan')) {
      return NotificationTarget(NotificationTargetType.plan, entityId);
    }
    return switch (entity) {
      'appointment' => NotificationTarget(
        NotificationTargetType.appointment,
        entityId,
      ),
      'billing' => NotificationTarget(NotificationTargetType.billing, entityId),
      'visit_payment_request' => NotificationTarget(
        NotificationTargetType.visitPayment,
        entityId,
      ),
      'slot_offer' => NotificationTarget(
        NotificationTargetType.slotOffer,
        entityId,
      ),
      _ => null,
    };
  }

  /// Which device mute a banner for this notice answers to.
  static PushChannel channelOf(NotificationItem item) {
    if (item.event.startsWith('appointment.reminder'))
      return PushChannel.reminder;
    if (item.category == 'billing') return PushChannel.payment;
    return PushChannel.statusUpdate;
  }

  // --- Time. ---

  /// The clinic's calendar day, `YYYY-MM-DD`, in Asia/Manila (UTC+8, no DST).
  static String manilaDate(DateTime now) {
    final m = now.toUtc().add(const Duration(hours: 8));
    return '${m.year.toString().padLeft(4, '0')}-${_two(m.month)}-${_two(m.day)}';
  }

  /// `created_at` age the way the website writes it: `Just now`, `5m ago`,
  /// `3h ago`, `2d ago`. Empty for a time in the future.
  static String relativeAge(DateTime at, DateTime now) {
    final diff = now.difference(at);
    if (diff.isNegative) return '';
    final m = diff.inMinutes;
    if (m < 1) return 'Just now';
    if (m < 60) return '${m}m ago';
    final h = m ~/ 60;
    if (h < 24) return '${h}h ago';
    return '${h ~/ 24}d ago';
  }

  /// The line above the title: actor and age for an addressed notice, the
  /// derived notice's own byline otherwise (`notifWhen` in notifications.js).
  static String byline(NotificationItem item, DateTime now) {
    if (item.isAddressed) {
      final who = (item.actorName ?? '').trim();
      final when = relativeAge(item.createdAt, now);
      if (who.isNotEmpty && when.isNotEmpty) return '$who · $when';
      return who.isNotEmpty ? who : when;
    }
    final meta = (item.meta ?? '').trim();
    if (meta.isNotEmpty) return meta;
    final mins = (now.difference(item.sortAt).inSeconds / 60).round();
    if (mins < 1) return 'Just now';
    if (mins < 60) return '${mins}m ago';
    final hrs = (mins / 60).round();
    if (hrs < 24) return '${hrs}h ago';
    final days = (hrs / 24).round();
    if (days < 7) return '${days}d ago';
    final local = item.sortAt.toUtc().add(const Duration(hours: 8));
    return '${_months[local.month - 1]} ${local.day}';
  }

  /// The day heading a notice sits under (`_notifDayBucket`), on Manila days.
  static String dayBucket(NotificationItem item, DateTime now) {
    final day = DateTime.parse(manilaDate(item.sortAt));
    final today = DateTime.parse(manilaDate(now));
    final diff = (day.difference(today).inHours / 24).round();
    if (diff > 1) return 'Upcoming';
    if (diff == 1) return 'Tomorrow';
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff > -7) return 'This week';
    return 'Earlier';
  }

  /// "Sep 28, 2026 · 10:00 AM" from a stored `appointment_date` and
  /// `appointment_time` — the website's `_fmtApptDate`. Reads the stored
  /// strings, so the clinic's day and time are shown whatever the phone's
  /// time zone.
  static String formatSchedule(String rawDate, String rawTime) {
    var out = '';
    final date = DateTime.tryParse(rawDate);
    if (date != null)
      out = '${_months[date.month - 1]} ${date.day}, ${date.year}';
    final parts = rawTime.split(':');
    final hour = int.tryParse(parts.first);
    if (rawTime.isNotEmpty && hour != null) {
      final minute = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : '00';
      final time =
          '${hour % 12 == 0 ? 12 : hour % 12}:$minute ${hour >= 12 ? 'PM' : 'AM'}';
      out = out.isEmpty ? time : '$out · $time';
    }
    return out;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}
