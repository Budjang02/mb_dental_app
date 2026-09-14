import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/models/patient.dart';
import 'package:mb_dental_app/repositories/patient_api.dart';
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

  group('downpayment', () {
    test('is 20% of the visit, rounded to centavos', () {
      expect(downPaymentFor(1000), 200);
      expect(downPaymentFor(1234.56), 246.91);
      expect(downPaymentFor(0), 0);
    });
  });

  group('InsufficientWalletBalanceException', () {
    test('carries the shortfall, so the screen can name the top-up', () {
      const e = InsufficientWalletBalanceException(available: 150, required: 400);
      expect(e.shortfall, 250);
    });

    test('never reports a negative shortfall', () {
      const e = InsufficientWalletBalanceException(available: 900, required: 400);
      expect(e.shortfall, 0);
    });
  });

  group('checkoutWithWallet', () {
    test('does nothing without a loaded patient record', () async {
      // No chart means no wallet to spend and no patient to bill, so the call
      // must not reach the network.
      expect(await PatientRepository().checkoutWithWallet(
            serviceIds: const ['procedure-1'],
            date: DateTime(2026, 9, 17),
            timeSlot: '10:00 AM',
            durationMinutes: 30,
            totalPrice: 1000,
            amountToPay: 200,
          ),
          isNull);
    });

    test('refuses an account the clinic has not approved, before any request', () async {
      PatientRepository().seedForTest(patient: _patient(), isApprovedForBooking: false);
      expect(
        PatientRepository().checkoutWithWallet(
          serviceIds: const ['procedure-1'],
          date: DateTime(2026, 9, 17),
          timeSlot: '10:00 AM',
          durationMinutes: 30,
          totalPrice: 1000,
          amountToPay: 200,
        ),
        throwsA(isA<PatientNotApprovedException>()),
      );
    });
  });

  group('balance', () {
    test('is what the repository reports until the server says otherwise', () {
      final repository = PatientRepository();
      repository.seedForTest(patient: _patient(), walletBalance: 750);
      expect(repository.walletBalance, 750);
      // The screen's own check is against this figure; the database re-checks it
      // under a row lock at checkout, which is what actually guards the wallet.
      expect(repository.walletBalance < downPaymentFor(5000), isTrue);
    });
  });
}
