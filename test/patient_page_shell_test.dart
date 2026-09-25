import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mb_dental_app/models/patient.dart';
import 'package:mb_dental_app/repositories/load_state.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/services/network_service.dart';
import 'package:mb_dental_app/widgets/patient_page_shell.dart';
import 'package:mb_dental_app/widgets/section_states.dart';
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

/// A page taller than the screen, so a failure to scroll is a real failure and
/// not just content that happens to fit.
Widget _tallPage() => ListView(
      children: [
        for (int i = 0; i < 40; i++) SizedBox(height: 60, child: Text('row $i')),
      ],
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  // The shell asks Supabase whether anyone is signed in, so the client has to
  // exist. Pointed at a throwaway project: no request is ever issued.
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

  group('PatientPageShell', () {
    testWidgets('shows the page and lets it scroll once the record has loaded',
        (tester) async {
      PatientRepository().seedForTest(patient: _patient());
      await tester.pumpWidget(_wrap(PatientPageShell(child: _tallPage())));
      await tester.pump();

      expect(find.text('row 0'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      // The first row has scrolled away, which is the whole point.
      expect(find.text('row 0'), findsNothing);
    });

    testWidgets('builds the page before any record has arrived', (tester) async {
      // The regression this whole change exists for: the old gate replaced the
      // page with a skeleton, and then with a full-screen error, so a patient
      // could not reach any part of the app while one request was failing.
      await tester.pumpWidget(_wrap(PatientPageShell(child: _tallPage())));
      await tester.pump();

      expect(find.text('row 0'), findsOneWidget);
    });

    testWidgets('keeps the page up and scrollable while nothing is loaded',
        (tester) async {
      await tester.pumpWidget(_wrap(PatientPageShell(child: _tallPage())));
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('row 0'), findsNothing);
    });

    testWidgets('puts pull-to-refresh over the page', (tester) async {
      await tester.pumpWidget(_wrap(PatientPageShell(child: _tallPage())));
      await tester.pump();

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });
  });

  group('classifyFailure', () {
    test('a dropped connection is offline, and offline is retryable', () {
      final status = classifyFailure(const SocketException('no route'));
      expect(status.failure, LoadFailure.offline);
      expect(status.isRetryable, isTrue);
      expect(status.message, isNotNull);
    });

    test('a stalled request is a timeout, and a timeout is retryable', () {
      final status = classifyFailure(TimeoutException('too slow', kRequestTimeout));
      expect(status.failure, LoadFailure.timeout);
      expect(status.isRetryable, isTrue);
    });

    test('a DNS or HTTP client failure is safe and retryable', () {
      final status = classifyFailure(http.ClientException('Failed host lookup: project.supabase.co'));
      expect(status.failure, LoadFailure.offline);
      expect(status.isRetryable, isTrue);
      expect(status.message, kServerConnectionMessage);
      expect(status.message, isNot(contains('supabase.co')));
    });

    test('an RLS refusal is a permission failure and is not retried', () {
      final status = classifyFailure(
        const PostgrestException(message: 'permission denied for table patients', code: '42501'),
      );
      expect(status.failure, LoadFailure.permission);
      expect(status.isRetryable, isFalse);
    });

    test('a rejected session is authentication failure, not an RLS failure', () {
      final status = classifyFailure(
        const PostgrestException(message: 'JWT is invalid', code: '401'),
      );
      expect(status.failure, LoadFailure.unauthenticated);
      expect(status.isRetryable, isFalse);
    });

    test('an HTTP 403 is an authorization failure and is not retried', () {
      final status = classifyFailure(
        const PostgrestException(message: 'forbidden', code: '403'),
      );
      expect(status.failure, LoadFailure.permission);
      expect(status.isRetryable, isFalse);
    });

    test('an invalid HTTP 400 request is not treated as offline', () {
      final status = classifyFailure(
        const PostgrestException(message: 'bad request', code: '400'),
      );
      expect(status.failure, LoadFailure.request);
      expect(status.isRetryable, isFalse);
    });

    test('a missing table is a schema failure and is not retried', () {
      final status = classifyFailure(
        const PostgrestException(message: 'relation does not exist', code: '42P01'),
      );
      expect(status.failure, LoadFailure.schema);
      expect(status.isRetryable, isFalse);
    });

    test('an expired session is unauthenticated and is not retried', () {
      final status = classifyFailure(const AuthException('JWT expired'));
      expect(status.failure, LoadFailure.unauthenticated);
      expect(status.isRetryable, isFalse);
    });

    test('no patient-facing message carries the database detail', () {
      final status = classifyFailure(
        const PostgrestException(
          message: 'permission denied for table patients',
          code: '42501',
        ),
      );
      expect(status.message, isNot(contains('patients')));
      expect(status.message, isNot(contains('42501')));
    });
  });

  group('runWithRetry', () {
    test('retries a dropped connection and returns the later success', () async {
      var calls = 0;
      final value = await runWithRetry<int>(() async {
        calls++;
        if (calls == 1) throw const SocketException('flaky');
        return 7;
      });
      expect(value, 7);
      expect(calls, 2);
    });

    test('does not retry a permission failure', () async {
      var calls = 0;
      await expectLater(
        runWithRetry<int>(() async {
          calls++;
          throw const PostgrestException(message: 'denied', code: '42501');
        }),
        throwsA(isA<PostgrestException>()),
      );
      expect(calls, 1);
    });

    test('gives up rather than hanging on a request that never answers', () async {
      await expectLater(
        runWithRetry<int>(
          () => Completer<int>().future,
          attempts: 1,
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('section state', () {
    test('a fresh repository has looked at nothing yet', () {
      for (final section in SyncSection.values) {
        expect(PatientRepository().statusOf(section).isPending, isTrue,
            reason: '$section should not claim to be loaded');
      }
    });

    test('a pending section is never treated as empty-and-done', () {
      // The distinction the whole design turns on: "you have no records" and
      // "we have not looked yet" must not render the same.
      expect(SectionStatus.idle.isPending, isTrue);
      expect(SectionStatus.loading.isPending, isTrue);
      expect(SectionStatus.ready.isPending, isFalse);
    });

    test('a failed section is not pending, so it shows an error not a skeleton', () {
      final failed = classifyFailure(const SocketException('down'));
      expect(failed.isPending, isFalse);
      expect(failed.hasFailed, isTrue);
    });

    test('an identity failure is what every section reports', () {
      // Nothing can be fetched without a chart id, so each section says the
      // same thing rather than inventing its own reason.
      expect(
        PatientRepository().effectiveStatusOf(SyncSection.appointments),
        PatientRepository().statusOf(SyncSection.appointments),
      );
    });

    test('a seeded record marks every section loaded and the balance known', () {
      PatientRepository().seedForTest(patient: _patient(), walletBalance: 120);
      for (final section in SyncSection.values) {
        expect(PatientRepository().statusOf(section).isReady, isTrue);
      }
      expect(PatientRepository().isWalletBalanceKnown, isTrue);
      expect(PatientRepository().walletBalance, 120);
    });

    test('clearing forgets the balance rather than reporting zero as checked', () {
      PatientRepository().seedForTest(patient: _patient(), walletBalance: 120);
      PatientRepository().clear();
      expect(PatientRepository().isWalletBalanceKnown, isFalse);
      expect(PatientRepository().hasPatientRecord, isFalse);
    });
  });

  group('SectionErrorNotice', () {
    testWidgets('offers a retry for a failure a retry could fix', (tester) async {
      var retries = 0;
      await tester.pumpWidget(_wrap(
        SectionErrorNotice(
          status: classifyFailure(const SocketException('down')),
          onRetry: () async => retries++,
        ),
      ));
      await tester.pump();

      expect(find.text('Try Again'), findsOneWidget);
      await tester.tap(find.text('Try Again'));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('offers no retry for a failure a retry cannot fix', (tester) async {
      await tester.pumpWidget(_wrap(
        SectionErrorNotice(
          status: classifyFailure(
            const PostgrestException(message: 'denied', code: '42501'),
          ),
          onRetry: () async {},
        ),
      ));
      await tester.pump();

      expect(find.text('Try Again'), findsNothing);
    });

    testWidgets('shows progress instead of a second button while retrying',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SectionErrorNotice(
          status: classifyFailure(const SocketException('down')),
          isRetrying: true,
          onRetry: () async {},
        ),
      ));
      await tester.pump();

      expect(find.text('Try Again'), findsNothing);
      expect(find.text('Retrying'), findsOneWidget);
    });
  });
}
