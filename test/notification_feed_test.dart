import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/models/patient.dart';
import 'package:mb_dental_app/models/patient_message.dart';
import 'package:mb_dental_app/models/payment.dart';
import 'package:mb_dental_app/models/treatment.dart';
import 'package:mb_dental_app/repositories/notification_feed.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final DateTime _now = DateTime(2026, 9, 14, 9);

Appointment _appointment(
  String id,
  String rawStatus, {
  DateTime? date,
  String rawDate = '2026-09-20',
  String rawTime = '10:00:00',
  bool byClinic = false,
  DateTime? changedAt,
}) {
  final status = switch (rawStatus) {
    'Confirmed' || 'Ongoing' => AppointmentStatus.confirmed,
    'Cancelled' || 'No-Show' => AppointmentStatus.cancelled,
    'Completed' => AppointmentStatus.completed,
    _ => AppointmentStatus.pending,
  };
  return Appointment(
    id: id,
    serviceName: 'Dental Checkup',
    doctorName: 'Dr. Rey Vincent Bolasoc',
    date: date ?? DateTime(2026, 9, 20),
    timeSlot: '10:00 AM',
    status: status,
    createdAt: DateTime(2026, 9, 10, 8),
    statusChangedAt: changedAt,
    rawDate: rawDate,
    rawTime: rawTime,
    rawStatus: rawStatus,
    isSelfBooked: !byClinic,
  );
}

TreatmentPlanSummary _plan(
  String id, {
  String status = 'active',
  String? updatedAt,
  String createdAt = '2026-09-01T08:00:00+00:00',
}) =>
    TreatmentPlanSummary(
      id: id,
      title: 'Plan $id',
      status: status,
      stamp: updatedAt ?? createdAt,
      wasUpdated: updatedAt != null && updatedAt != createdAt,
      updatedAt: updatedAt == null ? null : DateTime.parse(updatedAt),
      changedAt: DateTime.parse(updatedAt ?? createdAt),
    );

Iterable<String> _keys(List<FeedNotice> feed) => feed.map((n) => n.item.id);

Iterable<String> _sharedKeys(List<FeedNotice> feed) =>
    _keys(feed).where(NotificationFeed.isShared);

void main() {
  group('shared keys', () {
    test('booked| only when booked_by is exactly clinic', () {
      final feed = NotificationFeed.build(
        appointments: [
          _appointment('clinic', 'Pending', byClinic: true),
          _appointment('self', 'Pending'),
        ],
        now: _now,
      );
      expect(_sharedKeys(feed), containsAll(['booked|clinic', 'awaiting|self']));
      // A clinic booking still pending is not "awaiting" the patient's request.
      expect(_sharedKeys(feed), isNot(contains('awaiting|clinic')));
      expect(_sharedKeys(feed), isNot(contains('booked|self')));
    });

    test('confirmed|<appointment_date>|<appointment_time> from the raw column text', () {
      final feed = NotificationFeed.build(
        appointments: [_appointment('a1', 'Confirmed', rawDate: '2026-09-20', rawTime: '10:00')],
        now: _now,
      );
      expect(_sharedKeys(feed), ['confirmed|2026-09-20|10:00']);
    });

    test('rows outside Confirmed/Pending produce no shared notice at all', () {
      final feed = NotificationFeed.build(
        appointments: [
          _appointment('on', 'Ongoing', byClinic: true, date: DateTime(2026, 9, 14), rawDate: '2026-09-14'),
          _appointment('ca', 'Cancelled', byClinic: true, date: DateTime(2026, 9, 15), rawDate: '2026-09-15'),
          _appointment('co', 'Completed', byClinic: true),
          _appointment('ns', 'No-Show', byClinic: true),
        ],
        now: _now,
      );
      expect(_sharedKeys(feed), isEmpty);
    });

    test('reminder| fires 0-2 calendar days out, whatever the time of day', () {
      final feed = NotificationFeed.build(
        appointments: [
          // 8:00 AM today: already past at 9:00 AM, still counts.
          _appointment('past-today', 'Confirmed',
              date: DateTime(2026, 9, 14), rawDate: '2026-09-14', rawTime: '08:00:00'),
          _appointment('in2', 'Pending',
              date: DateTime(2026, 9, 16), rawDate: '2026-09-16', rawTime: '10:00:00'),
          _appointment('in3', 'Confirmed',
              date: DateTime(2026, 9, 17), rawDate: '2026-09-17', rawTime: '10:00:00'),
          _appointment('yesterday', 'Confirmed',
              date: DateTime(2026, 9, 13), rawDate: '2026-09-13', rawTime: '10:00:00'),
        ],
        now: _now,
      );
      final reminders = _sharedKeys(feed).where((k) => k.startsWith('reminder|'));
      expect(reminders, unorderedEquals(['reminder|2026-09-14|08:00:00', 'reminder|2026-09-16|10:00:00']));
    });

    test('rcpt|<payment_receipts.id>', () {
      final feed = NotificationFeed.build(
        billing: [
          Payment(
            id: 'billing-row',
            referenceNo: 'OR-1',
            procedureName: 'Cleaning',
            doctorName: '',
            amount: 1500,
            billedOn: DateTime(2026, 9, 11),
            status: 'Paid',
            invoiceNo: 'INV-1',
            receiptNo: 'OR-1',
            receiptId: 'receipt-uuid',
          ),
        ],
        now: _now,
      );
      expect(_sharedKeys(feed), ['rcpt|receipt-uuid']);
    });

    test('plan|<id>|<updated_at ?? created_at>, any status, new key after an edit', () {
      final created = NotificationFeed.build(plans: [_plan('p1')], now: _now);
      expect(_sharedKeys(created), ['plan|p1|2026-09-01T08:00:00+00:00']);
      expect(created.single.item.title, 'New treatment plan');

      final edited = NotificationFeed.build(
        plans: [_plan('p1', updatedAt: '2026-09-12T11:30:00.123456+00:00')],
        state: {'plan|p1|2026-09-01T08:00:00+00:00': NotificationState(readAt: DateTime(2026, 9, 2))},
        now: _now,
      );
      expect(_sharedKeys(edited), ['plan|p1|2026-09-12T11:30:00.123456+00:00']);
      expect(edited.single.item.isRead, isFalse);
      expect(edited.single.item.title, 'Treatment plan updated');

      final done = NotificationFeed.build(
        plans: [
          _plan('c', status: 'completed', updatedAt: '2026-09-12T00:00:00+00:00'),
          _plan('x', status: 'cancelled', updatedAt: '2026-09-11T00:00:00+00:00'),
        ],
        now: _now,
      );
      expect(_sharedKeys(done), hasLength(2));
      expect(done.firstWhere((n) => n.item.id.startsWith('plan|c|')).item.title,
          'Treatment plan completed');
    });

    test('plans: newest 10 by updated_at desc, a null updated_at first', () {
      final plans = [
        for (var i = 0; i < 11; i++)
          _plan('u$i', updatedAt: '2026-09-${(i + 1).toString().padLeft(2, '0')}T00:00:00+00:00'),
        _plan('never-updated', createdAt: '2026-08-01T00:00:00+00:00'),
      ];
      final keys = _sharedKeys(NotificationFeed.build(plans: plans, now: _now)).toList();
      expect(keys, hasLength(10));
      expect(keys, contains('plan|never-updated|2026-08-01T00:00:00+00:00'));
      // The two oldest `updated_at` values fall off.
      expect(keys.any((k) => k.startsWith('plan|u0|')), isFalse);
      expect(keys.any((k) => k.startsWith('plan|u1|')), isFalse);
    });

    test('read and dismissed state from notification_state is applied by key', () {
      final feed = NotificationFeed.build(
        appointments: [_appointment('read', 'Pending'), _appointment('gone', 'Pending')],
        state: {
          'awaiting|read': NotificationState(readAt: DateTime(2026, 9, 13)),
          'awaiting|gone': NotificationState(readAt: DateTime(2026, 9, 13), dismissedAt: DateTime(2026, 9, 13)),
        },
        now: _now,
      );
      expect(_keys(feed), ['awaiting|read']);
      expect(feed.single.item.isRead, isTrue);
    });
  });

  group('not shared', () {
    test('cancelled, completed, due and wallet notices are app-only', () {
      final feed = NotificationFeed.build(
        appointments: [
          _appointment('ca', 'Cancelled', changedAt: DateTime(2026, 9, 13)),
          _appointment('co', 'Completed', changedAt: DateTime(2026, 9, 12)),
        ],
        billing: [
          Payment(
            id: 'b1',
            referenceNo: 'INV-1',
            procedureName: 'Cleaning',
            doctorName: '',
            amount: 900,
            billedOn: DateTime(2026, 9, 11),
            status: 'Unpaid',
            invoiceNo: 'INV-1',
          ),
        ],
        now: _now,
      );
      expect(_keys(feed), unorderedEquals(['local:cancelled:ca', 'local:completed:co', 'local:due:b1']));
      expect(_keys(feed).every(NotificationFeed.isLocal), isTrue);
      expect(_keys(feed).any(NotificationFeed.isShared), isFalse);
    });

    test('notifications table rows are neither shared, local nor messages', () {
      const uuid = '3f1c9a52-8a8e-4a57-9d1e-7c1f5f9e2b10';
      expect(NotificationFeed.isDerived(uuid), isFalse);
      expect(NotificationFeed.isShared('confirmed|2026-09-20|10:00:00'), isTrue);
      expect(NotificationFeed.isShared('local:due:x'), isFalse);
    });
  });

  group('Appointment raw columns', () {
    test('a locally built booking spells its columns the way Postgres returns them', () {
      final a = Appointment(
        id: 'x',
        serviceName: 's',
        doctorName: '',
        date: DateTime(2026, 9, 5),
        timeSlot: '01:30 PM',
        status: AppointmentStatus.pending,
      );
      expect(a.rawDate, '2026-09-05');
      expect(a.rawTime, '13:30:00');
      expect(a.rawStatus, 'Pending');

      final moved = a.copyWith(date: DateTime(2026, 9, 6), timeSlot: '10:00 AM');
      expect(moved.rawDate, '2026-09-06');
      expect(moved.rawTime, '10:00:00');
    });
  });

  group('PatientRepository', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
    });

    tearDown(() => PatientRepository().clear());

    Patient patient() => Patient(
          id: 'p',
          patientCode: 'P-1',
          firstName: 'Test',
          lastName: 'Patient',
          username: 'test',
          email: 'test@example.com',
          phone: '',
        );

    test('clinic messages count on the chat badge and never on the bell', () {
      PatientRepository().seedForTest(
        patient: patient(),
        messages: [
          PatientMessage(id: 'm1', body: 'See you', fromPatient: false, senderRole: 'clinic', sentAt: DateTime.now()),
        ],
      );
      expect(PatientRepository().unreadMessageCount, 1);
      expect(PatientRepository().notifications, isEmpty);
      expect(PatientRepository().unreadNotificationCount, 0);
    });

    test('next appointment: Confirmed or Pending, today onward, earliest date then time', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      String day(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final tomorrow = today.add(const Duration(days: 1));
      final yesterday = today.subtract(const Duration(days: 1));

      PatientRepository().seedForTest(
        patient: patient(),
        appointments: [
          _appointment('past-pending', 'Pending', date: yesterday, rawDate: day(yesterday)),
          _appointment('ongoing-today', 'Ongoing', date: today, rawDate: day(today), rawTime: '08:00:00'),
          _appointment('cancelled-today', 'Cancelled', date: today, rawDate: day(today), rawTime: '07:00:00'),
          _appointment('tomorrow-3pm', 'Confirmed', date: tomorrow, rawDate: day(tomorrow), rawTime: '15:00:00'),
          _appointment('tomorrow-10am', 'pending', date: tomorrow, rawDate: day(tomorrow), rawTime: '10:00:00'),
        ],
      );
      expect(PatientRepository().nextUpcomingAppointment?.id, 'tomorrow-10am');
    });

    test('the bell shows notices built from the record', () {
      PatientRepository().seedForTest(
        patient: patient(),
        appointments: [_appointment('a1', 'Confirmed')],
      );
      expect(PatientRepository().notifications.map((n) => n.id), contains('confirmed|2026-09-20|10:00:00'));
    });

    test('unread messages are the clinic\'s with no read_at; oldest first', () {
      PatientRepository().seedForTest(
        patient: patient(),
        messages: [
          PatientMessage(id: 'new', body: 'b', fromPatient: false, senderRole: 'clinic', sentAt: DateTime(2026, 9, 13)),
          PatientMessage(id: 'old', body: 'a', fromPatient: true, senderRole: 'patient', sentAt: DateTime(2026, 9, 12)),
        ],
      );
      expect(PatientRepository().messages.map((m) => m.id), ['old', 'new']);
      expect(PatientRepository().unreadMessageCount, 1);
    });
  });
}
