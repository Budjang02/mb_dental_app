import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/app/notification_style.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/models/notification.dart';
import 'package:mb_dental_app/models/patient.dart';
import 'package:mb_dental_app/models/treatment.dart';
import 'package:mb_dental_app/repositories/notification_feed.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/notification_row.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 2026-09-14 09:00 in Manila.
final DateTime _now = DateTime.utc(2026, 9, 14, 1);

Appointment _appointment(
  String id,
  String rawStatus, {
  String rawDate = '2026-09-20',
  String rawTime = '10:00:00',
  bool byClinic = false,
  String doctor = 'Dr. Rey Vincent Bolasoc',
  String service = 'Dental Checkup',
}) {
  final status = switch (rawStatus) {
    'Confirmed' || 'Ongoing' => AppointmentStatus.confirmed,
    'Cancelled' || 'No-Show' => AppointmentStatus.cancelled,
    'Completed' => AppointmentStatus.completed,
    _ => AppointmentStatus.pending,
  };
  return Appointment(
    id: id,
    serviceName: service,
    doctorName: doctor,
    date: DateTime.parse(rawDate),
    timeSlot: '10:00 AM',
    status: status,
    createdAt: DateTime(2026, 9, 10, 8),
    rawDate: rawDate,
    rawTime: rawTime,
    rawStatus: rawStatus,
    isSelfBooked: !byClinic,
  );
}

NotificationItem _row(
  String uuid, {
  String event = 'appointment.cancelled',
  String title = 'Your appointment was cancelled',
  String body = 'Sep 28, 2026 10:00 AM',
  String? actor = 'Maria Santos',
  DateTime? createdAt,
  DateTime? readAt,
  String entity = 'appointment',
  String entityId = 'appt-1',
}) =>
    NotificationItem(
      id: 'db|$uuid',
      title: title,
      body: body,
      createdAt: createdAt ?? _now.subtract(const Duration(days: 2)),
      isRead: readAt != null,
      readAt: readAt,
      event: event,
      actorName: actor,
      category: NotificationFeed.categoryOf(event),
      target: NotificationFeed.targetOf(event: event, entity: entity, entityId: entityId),
    );

TreatmentPlanSummary _plan(String id, {String? updatedAt, String status = 'active'}) {
  const created = '2026-09-01T08:00:00+00:00';
  return TreatmentPlanSummary(
    id: id,
    title: 'Plan $id',
    status: status,
    stamp: updatedAt ?? created,
    wasUpdated: updatedAt != null && updatedAt != created,
    updatedAt: updatedAt == null ? null : DateTime.parse(updatedAt),
    changedAt: DateTime.parse(updatedAt ?? created),
  );
}

List<String> _ids(List<NotificationItem> items) => [for (final n in items) n.id];

void main() {
  group('derived notices match the website', () {
    test('keys, titles and wording follow js/render-patient.js', () {
      final feed = NotificationFeed.build(
        appointments: [
          _appointment('a1', 'Confirmed', rawDate: '2026-09-15'),
          _appointment('a2', 'Pending', rawDate: '2026-09-20'),
          _appointment('a3', 'Pending', rawDate: '2026-09-22', byClinic: true),
        ],
        now: _now,
      );
      expect(_ids(feed), [
        'confirmed|2026-09-15|10:00:00',
        'reminder|2026-09-15|10:00:00',
        'awaiting|a2',
        'booked|a3',
      ]);
      expect(feed[0].title, 'Appointment Confirmed');
      expect(feed[0].body, 'Sep 15, 2026 · 10:00 AM — Dr. Rey Vincent Bolasoc');
      expect(feed[0].meta, 'Tomorrow');
      expect(feed[1].title, 'Upcoming Appointment');
      expect(feed[1].body, 'Reminder: Dental Checkup tomorrow');
      expect(feed[2].body, 'Sep 20, 2026 · 10:00 AM — the clinic will confirm this shortly');
      expect(feed[3].title, 'The clinic booked an appointment for you');
      expect(feed[3].target, const NotificationTarget(NotificationTargetType.appointment, 'a3'));
    });

    test('past visits and closed statuses are not in the feed', () {
      final feed = NotificationFeed.build(
        appointments: [
          _appointment('old', 'Confirmed', rawDate: '2026-09-13'),
          _appointment('gone', 'Cancelled', rawDate: '2026-09-20'),
          _appointment('pay', 'Pending Payment', rawDate: '2026-09-15'),
        ],
        now: _now,
      );
      // Pending Payment is in the website's query: it gets a reminder, and no
      // "awaiting" (that is for status Pending only).
      expect(_ids(feed), ['reminder|2026-09-15|10:00:00']);
    });

    test('"today" is the clinic day in Manila, not UTC', () {
      // 23:30 UTC on the 14th is already the 15th in Manila.
      final lateUtc = DateTime.utc(2026, 9, 14, 23, 30);
      final feed = NotificationFeed.build(
        appointments: [_appointment('a', 'Confirmed', rawDate: '2026-09-14')],
        now: lateUtc,
      );
      expect(feed, isEmpty);
    });

    test('an unnamed dentist reads "your doctor", as on the website', () {
      final feed = NotificationFeed.build(
        appointments: [_appointment('a', 'Confirmed', rawDate: '2026-09-20', doctor: '')],
        now: _now,
      );
      expect(feed.single.body, endsWith('— your doctor'));
    });

    test('receipts and plans', () {
      final feed = NotificationFeed.build(
        receipts: [
          ReceiptNotice(
            id: 'r1',
            issuedAt: DateTime.utc(2026, 9, 12),
            referenceNo: 'OR-0001',
            procedureName: 'Cleaning',
            amountDue: 1500,
            paymentMethod: 'Cash',
          ),
        ],
        plans: [_plan('p1'), _plan('p2', updatedAt: '2026-09-10T08:00:00+00:00', status: 'completed')],
        now: _now,
      );
      expect(_ids(feed), [
        'rcpt|r1',
        'plan|p1|2026-09-01T08:00:00+00:00',
        'plan|p2|2026-09-10T08:00:00+00:00',
      ]);
      expect(feed[0].body, 'Cleaning — ₱1,500.00 (Cash)');
      expect(feed[0].target!.type, NotificationTargetType.billing);
      expect(feed[1].title, 'New treatment plan');
      expect(feed[2].title, 'Treatment plan completed');
      expect(feed[2].target!.type, NotificationTargetType.plan);
    });
  });

  group('addressed rows', () {
    test('lead the feed, newest first, and carry their own read_at', () {
      final feed = NotificationFeed.build(
        addressed: [
          _row('old', createdAt: _now.subtract(const Duration(days: 3)), readAt: _now),
          _row('new', createdAt: _now.subtract(const Duration(hours: 3))),
        ],
        appointments: [_appointment('a2', 'Pending')],
        now: _now,
      );
      expect(_ids(feed), ['db|new', 'db|old', 'awaiting|a2']);
      expect(feed[0].isRead, isFalse);
      expect(feed[1].isRead, isTrue);
    });

    test('a derived notice an addressed row already says is dropped', () {
      final feed = NotificationFeed.build(
        addressed: [
          _row('c', event: 'appointment.confirmed', title: 'Your appointment is confirmed', entityId: 'a1'),
        ],
        covered: {'appointment.confirmed|a1', 'billing.receipt|r1'},
        appointments: [_appointment('a1', 'Confirmed'), _appointment('a2', 'Confirmed', rawTime: '14:00:00')],
        receipts: [ReceiptNotice(id: 'r1', issuedAt: DateTime.utc(2026, 9, 12))],
        now: _now,
      );
      expect(_ids(feed), ['db|c', 'confirmed|2026-09-20|14:00:00']);
    });

    test('two reschedules stay two notices', () {
      final feed = NotificationFeed.build(
        addressed: [
          _row('r1', event: 'appointment.rescheduled', title: 'Your appointment was rescheduled'),
          _row('r2', event: 'appointment.rescheduled', title: 'Your appointment was rescheduled'),
        ],
        now: _now,
      );
      expect(feed, hasLength(2));
    });

    test('where each kind opens', () {
      NotificationTarget? t(String event, String entity) =>
          NotificationFeed.targetOf(event: event, entity: entity, entityId: 'x');
      expect(t('appointment.cancelled', 'appointment')!.type, NotificationTargetType.appointment);
      expect(t('billing.charged', 'billing')!.type, NotificationTargetType.billing);
      expect(t('clinical.treatment_plan', 'patient')!.type, NotificationTargetType.plan);
      expect(t('visit_payment_requested', 'visit_payment_request')!.type,
          NotificationTargetType.visitPayment);
      expect(t('appointment.earlier_slot', 'slot_offer')!.type, NotificationTargetType.slotOffer);
      expect(t('patient.updated', 'patient'), isNull);
    });
  });

  group('shared state and settings', () {
    test('notification_state read and dismissed apply to any key', () {
      final feed = NotificationFeed.build(
        addressed: [_row('a'), _row('b')],
        appointments: [_appointment('p', 'Pending')],
        state: {
          'db|a': NotificationState(readAt: _now),
          'db|b': NotificationState(readAt: _now, dismissedAt: _now),
          'awaiting|p': NotificationState(readAt: _now),
        },
        now: _now,
      );
      expect(_ids(feed), ['db|a', 'awaiting|p']);
      expect(feed.every((n) => n.isRead), isTrue);
    });

    test('a switched-off category leaves the feed, and so the count', () {
      final feed = NotificationFeed.build(
        addressed: [_row('bill', event: 'billing.charged', entity: 'billing')],
        appointments: [_appointment('p', 'Pending')],
        prefs: const NotificationPrefs(billing: false),
        now: _now,
      );
      expect(_ids(feed), ['awaiting|p']);
    });
  });

  group('time', () {
    test('event age, as the website writes it', () {
      expect(NotificationFeed.relativeAge(_now, _now), 'Just now');
      expect(NotificationFeed.relativeAge(_now.subtract(const Duration(minutes: 5)), _now), '5m ago');
      expect(NotificationFeed.relativeAge(_now.subtract(const Duration(hours: 3, minutes: 50)), _now),
          '3h ago');
      expect(NotificationFeed.relativeAge(_now.subtract(const Duration(days: 2, hours: 20)), _now),
          '2d ago');
    });

    test('byline is actor and age; the schedule stays in the body', () {
      final n = _row('x');
      expect(NotificationFeed.byline(n, _now), 'Maria Santos · 2d ago');
      expect(n.body, 'Sep 28, 2026 10:00 AM');
      expect(NotificationFeed.byline(_row('y', actor: null), _now), '2d ago');
    });

    test('the schedule is read from the stored strings', () {
      expect(NotificationFeed.formatSchedule('2026-09-28', '10:00:00'), 'Sep 28, 2026 · 10:00 AM');
      expect(NotificationFeed.formatSchedule('2026-09-28', '00:30:00'), 'Sep 28, 2026 · 12:30 AM');
      expect(NotificationFeed.formatSchedule('2026-09-28', ''), 'Sep 28, 2026');
    });
  });

  test('tones and icons follow the event key', () {
    expect(NotificationStyle.toneOf('appointment.cancelled'), NotificationTone.red);
    expect(NotificationStyle.toneOf('appointment.confirmed'), NotificationTone.green);
    expect(NotificationStyle.toneOf('appointment.rescheduled'), NotificationTone.purple);
    expect(NotificationStyle.toneOf('appointment.reminder'), NotificationTone.orange);
    expect(NotificationStyle.toneOf('appointment.pending'), NotificationTone.orange);
    expect(NotificationStyle.toneOf('appointment.booked_for_you'), NotificationTone.blue);
    expect(NotificationStyle.toneOf('appointment.assigned'), NotificationTone.blue);
    expect(NotificationStyle.toneOf('appointment.paid'), NotificationTone.green);
    expect(NotificationStyle.toneOf('visit_payment_requested'), NotificationTone.orange);
    expect(NotificationStyle.toneOf('appointment.earlier_slot'), NotificationTone.purple);
    expect(NotificationStyle.toneOf('billing.receipt'), NotificationTone.blue);
    expect(NotificationStyle.toneOf('billing.voided'), NotificationTone.red);
    expect(NotificationStyle.toneOf('treatment_plan'), NotificationTone.purple);
    expect(NotificationStyle.toneOf('something.new'), NotificationTone.gray);
    expect(NotificationStyle.iconColor(NotificationTone.red, dark: false), const Color(0xFFB91C1C));
  });

  group('on screen', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
    });
    tearDown(() => PatientRepository().clear());

    testWidgets('an unread row has the teal bar; reading it removes only the bar',
        (tester) async {
      Future<void> pump(NotificationItem n) => tester.pumpWidget(
            MaterialApp(home: Scaffold(body: NotificationRow(notification: n))),
          );
      bool hasBar() => find
          .byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == NotificationStyle.unreadIndicator)
          .evaluate()
          .isNotEmpty;

      final n = _row('x', createdAt: DateTime.now().subtract(const Duration(days: 2)));
      await pump(n);
      expect(find.text('Maria Santos · 2d ago'), findsOneWidget);
      expect(find.text('Your appointment was cancelled'), findsOneWidget);
      expect(find.text('Sep 28, 2026 10:00 AM'), findsOneWidget);
      expect(hasBar(), isTrue);

      await pump(n.copyWith(isRead: true, readAt: DateTime.now()));
      expect(hasBar(), isFalse);
      expect(find.byType(NotificationRow), findsOneWidget);
    });

    test('the badge counts the feed, drops on a tap, and is zero while off', () async {
      final repository = PatientRepository();
      repository.seedForTest(
        patient: Patient(
          id: 'p',
          patientCode: 'PAT-1',
          firstName: 'Test',
          lastName: 'Patient',
          username: 't',
          email: 't@example.com',
          phone: '',
        ),
        notifications: [_row('a'), _row('b')],
      );
      expect(repository.unreadNotificationCount, 2);
      // No session in a test, so nothing is written; the local copy is what
      // this covers. The writes themselves are PatientApi.markNoticesRead.
      repository.seedForTest(
        patient: repository.patient,
        notifications: [_row('a'), _row('b')],
        notificationState: {'db|a': NotificationState(readAt: _now)},
      );
      expect(repository.unreadNotificationCount, 1);
      repository.seedForTest(
        patient: repository.patient,
        notifications: [_row('a'), _row('b')],
        notificationPrefs: const NotificationPrefs(enabled: false),
      );
      expect(repository.unreadNotificationCount, 0);
    });
  });
}
