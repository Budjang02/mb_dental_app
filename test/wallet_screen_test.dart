import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/models/patient.dart';
import 'package:mb_dental_app/models/payment.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/screens/wallet/billing_receipts.dart';
import 'package:mb_dental_app/screens/wallet/pay_screens.dart';
import 'package:mb_dental_app/screens/wallet/transaction_history_screen.dart';
import 'package:mb_dental_app/screens/wallet/wallet_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _patient = Patient(
  id: 'p',
  patientCode: 'PAT-1',
  firstName: 'Test',
  lastName: 'Patient',
  username: 't',
  email: 't@example.com',
  phone: '',
);

Payment _charge(String id, {String status = 'Unpaid', bool voided = false, String? receiptId}) => Payment(
      id: id,
      referenceNo: id,
      procedureName: 'Charge $id',
      doctorName: 'Dr. Reyes',
      amount: 750,
      billedOn: DateTime.utc(2026, 9, 1),
      status: status,
      invoiceNo: '',
      receiptId: receiptId,
      receiptNo: receiptId == null ? null : 'OR-$receiptId',
      voidedAt: voided ? DateTime.utc(2026, 9, 2) : null,
    );

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });
  tearDown(() => PatientRepository().clear());

  testWidgets('balance, Pay Bill count, clinic request, and hiding the balance', (tester) async {
    PatientRepository().seedForTest(
      patient: _patient,
      walletBalance: 1500,
      billing: [_charge('a'), _charge('b'), _charge('c', status: 'Paid'), _charge('d', voided: true)],
      visitRequests: [
        VisitPaymentRequest(
          id: 'r1',
          amount: 2400,
          status: 'pending',
          createdAt: DateTime.utc(2026, 9, 28),
          visitDate: '2026-09-28',
        ),
      ],
    );
    await _pump(tester, const WalletScreen());

    expect(find.text('₱1,500.00'), findsOneWidget);
    // The app pays through Pay using QR; Pay Bill is the website's.
    expect(find.textContaining('Pay Bill'), findsNothing);
    expect(find.text('Pay using QR'), findsOneWidget);
    expect(find.text('Cash In'), findsOneWidget);
    expect(find.text('All Dates'), findsOneWidget);
    expect(find.text('All Types'), findsOneWidget);
    expect(find.byTooltip('Transaction History & Billing'), findsOneWidget);
    expect(find.text('Payment request from the clinic'), findsOneWidget);
    expect(find.text('For your visit on Sep 28, 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide balance'));
    await tester.pump();
    expect(find.text('₱ ••••••'), findsOneWidget);
    expect(find.text('₱1,500.00'), findsNothing);
  });

  testWidgets('an unverified balance is never shown as a figure', (tester) async {
    PatientRepository().seedForTest(patient: _patient, walletBalance: 0, isWalletBalanceKnown: false);
    await _pump(tester, const WalletScreen());
    expect(find.text('₱0.00'), findsNothing);
    expect(find.text('₱ —'), findsOneWidget);
  });

  testWidgets('Pay Bill offers the wallet first only when it covers the charge', (tester) async {
    PatientRepository().seedForTest(patient: _patient, walletBalance: 100, billing: [_charge('a')]);
    await _pump(tester, const PayBillScreen());
    final picker = tester.widget<PayRailPicker>(find.byType(PayRailPicker));
    expect(picker.selected, 'gcash');
    expect(find.text('Charge a'), findsOneWidget);
    expect(find.text('Billed Sep 1, 2026'), findsOneWidget);
  });

  testWidgets('billing list: totals, status, voided struck through, documents pending', (tester) async {
    PatientRepository().seedForTest(
      patient: _patient,
      billing: [_charge('a', status: 'Paid', receiptId: 'r1'), _charge('b'), _charge('v', voided: true)],
    );
    await _pump(tester, const Scaffold(body: BillingReceiptsView()));
    expect(find.text('₱750.00'), findsWidgets);
    // The list alone: no summary tiles, no heading.
    expect(find.text('Outstanding Balance'), findsNothing);
    expect(find.text('Transaction History'), findsNothing);
    expect(find.textContaining('Unspecified'), findsOneWidget);
    final voided = tester.widgetList<Text>(find.text('₱750.00')).where((t) => t.style?.decoration == TextDecoration.lineThrough);
    expect(voided, hasLength(1));

    await tester.tap(find.text('Charge b'));
    await tester.pumpAndSettle();
    expect(find.text('Billing Overview'), findsOneWidget);
    expect(find.text('Official Invoice Pending'), findsOneWidget);
    expect(find.text('Receipt Pending'), findsOneWidget);
    // Information and breakdown share one card.
    expect(find.text('Billing Information'), findsOneWidget);
    expect(find.text('Payment Breakdown'), findsOneWidget);
  });

  testWidgets('Transaction History › Wallet renders its list (no crash)', (tester) async {
    PatientRepository().seedForTest(patient: _patient, walletBalance: 10);
    await _pump(tester, const TransactionHistoryScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('All Dates'), findsOneWidget);
    expect(find.text('No transactions yet. Cash in to get started.'), findsOneWidget);
  });

  testWidgets('balance card is compact: shorter than a payment card', (tester) async {
    PatientRepository().seedForTest(patient: _patient, walletBalance: 1500);
    await _pump(tester, const WalletScreen());
    final card = tester.getRect(find.ancestor(of: find.text('Available Balance'), matching: find.byType(ClipRRect)).first);
    expect(card.height, lessThan(card.width / 1.586));
  });

  testWidgets('overview: Paid badge lines up with the other values', (tester) async {
    PatientRepository().seedForTest(patient: _patient, billing: [_charge('a', status: 'Paid')]);
    await _pump(tester, BillingOverviewScreen(charge: _charge('a', status: 'Paid')));
    final doctor = tester.getRect(find.text('Dr. Reyes'));
    final paid = tester.getRect(find.text('Paid'));
    expect((paid.left - doctor.left).abs(), lessThanOrEqualTo(12));
  });
}
