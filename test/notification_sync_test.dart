import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/models/notification.dart';
import 'package:mb_dental_app/models/patient.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Patient _patient() => Patient(
      id: 'test-patient',
      patientCode: 'PAT-TEST-0001',
      firstName: 'Test',
      lastName: 'Patient',
      username: 'testpatient',
      email: 'test@example.com',
      phone: '+63 900 000 0000',
    );

NotificationItem _alert(String id, {bool isRead = false, DateTime? readAt}) =>
    NotificationItem(
      id: id,
      title: 'Alert $id',
      body: 'body',
      createdAt: DateTime(2026, 9, 1),
      isRead: isRead,
      readAt: readAt,
    );

/// The read state lives on the row, so a change made on the web platform
/// reaches this device as a realtime UPDATE rather than as a tap here. These
/// cover the path that applies such an update to the in-memory copy.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  setUp(() => PatientRepository().clear());
  tearDown(() => PatientRepository().clear());

  group('applyNotificationReadState', () {
    test('a read on the other platform clears the unread badge here', () {
      final repository = PatientRepository();
      repository.seedForTest(
        patient: _patient(),
        notifications: [_alert('a'), _alert('b')],
      );
      expect(repository.unreadNotificationCount, 2);

      final readAt = DateTime.utc(2026, 9, 12, 3, 30);
      repository.applyNotificationReadState('a', isRead: true, readAt: readAt);

      final updated = repository.notifications.firstWhere((n) => n.id == 'a');
      expect(updated.isRead, isTrue);
      expect(updated.readAt, readAt);
      expect(repository.unreadNotificationCount, 1);
    });

    test('an unread on the other platform brings the badge back', () {
      final repository = PatientRepository();
      repository.seedForTest(
        patient: _patient(),
        notifications: [_alert('a', isRead: true, readAt: DateTime.utc(2026, 9, 1))],
      );
      expect(repository.unreadNotificationCount, 0);

      repository.applyNotificationReadState('a', isRead: false, readAt: null);

      expect(repository.notifications.single.isRead, isFalse);
      expect(repository.notifications.single.readAt, isNull);
      expect(repository.unreadNotificationCount, 1);
    });

    test('notifies listeners only when the state actually changed', () {
      final repository = PatientRepository();
      repository.seedForTest(
        patient: _patient(),
        notifications: [_alert('a', isRead: true, readAt: DateTime.utc(2026, 9, 1))],
      );

      var notifications = 0;
      void listener() => notifications++;
      repository.addListener(listener);
      addTearDown(() => repository.removeListener(listener));

      // Same state as the row already holds - an echo of this device's own
      // write, which must not spin the tree.
      repository.applyNotificationReadState('a',
          isRead: true, readAt: DateTime.utc(2026, 9, 1));
      expect(notifications, 0);

      repository.applyNotificationReadState('a', isRead: false, readAt: null);
      expect(notifications, 1);
    });

    test('an id this session does not hold is ignored', () {
      final repository = PatientRepository();
      repository.seedForTest(patient: _patient(), notifications: [_alert('a')]);

      repository.applyNotificationReadState('not-mine', isRead: true, readAt: null);

      expect(repository.notifications.length, 1);
      expect(repository.unreadNotificationCount, 1);
    });
  });

  group('NotificationItem.copyWith', () {
    test('keeps every field it was not asked to change', () {
      final item = NotificationItem(
        id: 'a',
        title: 'Appointment confirmed',
        body: 'See you Thursday',
        createdAt: DateTime(2026, 9, 1),
        relatedAppointmentId: 'appt-1',
        relatedTransactionId: 'txn-1',
      );

      final read = item.copyWith(isRead: true, readAt: DateTime.utc(2026, 9, 2));

      expect(read.id, 'a');
      expect(read.title, 'Appointment confirmed');
      expect(read.body, 'See you Thursday');
      expect(read.createdAt, item.createdAt);
      expect(read.relatedAppointmentId, 'appt-1');
      expect(read.relatedTransactionId, 'txn-1');
      expect(read.isRead, isTrue);
      expect(read.readAt, DateTime.utc(2026, 9, 2));
    });
  });
}
