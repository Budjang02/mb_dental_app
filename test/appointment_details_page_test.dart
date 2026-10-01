import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/repositories/clinic_documents_api.dart';
import 'package:mb_dental_app/screens/appointments/appointment_details_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Appointment _appt({AppointmentStatus status = AppointmentStatus.confirmed, String raw = 'Confirmed'}) => Appointment(
      id: '6f1c2b1e-8a57-4c1e-9d0a-1b2c3d4e5f60',
      serviceName: 'Dental Checkup',
      doctorName: 'Jenneline Mariano',
      date: DateTime(2026, 10, 1),
      timeSlot: '10:00 AM',
      durationMinutes: 30,
      status: status,
      rawStatus: raw,
      rawDate: '2026-10-01',
      rawTime: '10:00:00',
      totalPrice: 500,
      amountPaid: 100,
      downpaymentAmount: 100,
      paymentMethod: 'Wallet',
      confirmationCode: 'E3XZSR',
      qrToken: '0123456789abcdef0123456789abcdef',
      downpaymentPaidAt: DateTime(2026, 9, 20),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  Future<void> pump(WidgetTester tester, Appointment a) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AppointmentDetailsPage(appointmentId: a.id, initial: a)));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('order, values and the confirmed-visit documents', (tester) async {
    await pump(tester, _appt());
    expect(tester.takeException(), isNull);

    // Opens at the top with the QR below the header.
    final qr = tester.getRect(find.text('Save QR Image'));
    expect(qr.top, greaterThan(kToolbarHeight));
    expect(qr.bottom, lessThan(844));

    // Appointment Information, then Payment Summary, in one scroll.
    final info = tester.getTopLeft(find.text('Appointment Information', skipOffstage: false)).dy;
    final pay = tester.getTopLeft(find.text('Payment Summary', skipOffstage: false)).dy;
    expect(pay, greaterThan(info));
    expect(qr.top, lessThan(info));

    expect(find.text('October 1, 2026', skipOffstage: false), findsOneWidget);
    expect(find.text('10:00 AM – 10:30 AM', skipOffstage: false), findsOneWidget);
    expect(find.text('Jenneline Mariano', skipOffstage: false), findsOneWidget);
    expect(find.text('₱500', skipOffstage: false), findsOneWidget);
    expect(find.text('₱100', skipOffstage: false), findsOneWidget);
    expect(find.text('₱400', skipOffstage: false), findsOneWidget);
    expect(find.text('Estimated Balance Due at Clinic', skipOffstage: false), findsOneWidget);

    // Confirmed: the verified deposit's receipt, and the invoice checked — a
    // failed check offers Retry rather than claiming none exists.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Download Deposit Receipt', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Retry loading invoice', skipOffstage: false).evaluate().isNotEmpty || find.text('Checking invoice…', skipOffstage: false).evaluate().isNotEmpty,
      isTrue,
    );
    expect(find.text('Reschedule', skipOffstage: false), findsOneWidget);
    expect(find.text('Cancel Appointment', skipOffstage: false), findsOneWidget);
    // No explanatory text under the two buttons.
    expect(find.textContaining('administrative fee', skipOffstage: false), findsNothing);
  });

  testWidgets('completed: Receipt and Invoice side by side', (tester) async {
    await pump(tester, _appt(status: AppointmentStatus.completed, raw: 'Completed'));
    await tester.pump(const Duration(seconds: 1));
    final receipt = tester.getRect(find.text('Download Receipt', skipOffstage: false));
    final invoice = tester.getRect(find.text('Download Invoice', skipOffstage: false));
    expect((receipt.center.dy - invoice.center.dy).abs(), lessThan(2));
    expect(receipt.left, lessThan(invoice.left));
  });

  testWidgets('Copy copies the code and says Copied!', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    await pump(tester, _appt());
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, ['E3XZSR']);
    expect(find.text('Copied!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Copy'), findsOneWidget);
  });

  test('unverified and forfeited deposits are not deducted', () {
    final unpaid = AppointmentMoney.compute(
      method: 'GCash',
      downpaymentAmount: 100,
      downpaymentPaid: false,
      rescheduleFeeTotal: 0,
      estimateMin: 500,
      estimateMax: 500,
    );
    expect(unpaid.paid, isFalse);
    expect(unpaid.balanceMin, 500);
    final forfeited = AppointmentMoney.compute(
      method: 'GCash',
      downpaymentAmount: 100,
      downpaymentPaid: true,
      depositForfeited: true,
      rescheduleFeeTotal: 0,
      estimateMin: 500,
      estimateMax: 500,
    );
    expect(forfeited.paid, isFalse);
    expect(forfeited.forfeited, isTrue);
    expect(forfeited.balanceMin, 500);
    final fees = AppointmentMoney.compute(
      method: 'GCash',
      downpaymentAmount: 100,
      downpaymentPaid: true,
      rescheduleFeeTotal: 20,
      estimateMin: 500,
      estimateMax: 500,
      billTotal: 500,
      billUnpaid: 500,
    );
    expect(fees.credited, 80);
    expect(fees.balanceMin, 420);
  });
}
