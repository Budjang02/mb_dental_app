import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/repositories/clinic_documents_api.dart';
import 'package:mb_dental_app/screens/appointments/appointment_confirmed_screen.dart';

Appointment _booking({AppointmentStatus status = AppointmentStatus.confirmed, bool paid = true}) => Appointment(
      id: 'appt-1',
      serviceName: 'Dental Checkup',
      doctorName: 'Dr. Jenneline Mariano',
      date: DateTime(2026, 10, 2),
      timeSlot: '10:00 AM',
      status: status,
      totalPrice: 1500,
      amountPaid: paid ? 300 : 0,
      downpaymentAmount: 300,
      downpaymentPaidAt: paid ? DateTime(2026, 9, 25) : null,
      paymentMethod: 'Wallet',
      confirmationCode: 'E3XZSR',
    );

AppointmentMoney _money({bool paid = true}) => AppointmentMoney.compute(
      method: 'Wallet',
      downpaymentAmount: 300,
      downpaymentPaid: paid,
      rescheduleFeeTotal: 0,
      estimateMin: 1500,
      estimateMax: 1500,
    );

Widget _screen(Appointment a, AppointmentMoney m) =>
    MaterialApp(home: AppointmentConfirmedScreen(appointmentId: a.id, preview: a, previewMoney: m));

void main() {
  testWidgets('shows the confirmation, the visit and the money', (tester) async {
    await tester.pumpWidget(_screen(_booking(), _money()));
    expect(find.text('Appointment Confirmed!'), findsOneWidget);
    expect(find.text('Your slot has been reserved successfully.'), findsOneWidget);
    expect(find.text('E3XZSR'), findsOneWidget);
    expect(find.text('Dental Checkup'), findsOneWidget);
    expect(find.text('Dr. Jenneline Mariano'), findsOneWidget);
    expect(find.text('₱1,500'), findsOneWidget); // Total Estimated Cost
    expect(find.text('₱300.00'), findsOneWidget); // Down Payment Paid
    expect(find.text('E-Wallet'), findsOneWidget); // Payment Method, its own row
    expect(find.text('₱1,200'), findsOneWidget); // Balance
    await tester.scrollUntilVisible(find.textContaining('10-minute grace period'), 200);
    expect(find.textContaining('10-minute grace period'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('View My Appointments'), 200);
    expect(find.text('Download Deposit Receipt'), findsOneWidget);
    expect(find.text('View My Appointments'), findsOneWidget);
  });

  testWidgets('Copy puts the confirmation code on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    await tester.pumpWidget(_screen(_booking(), _money()));
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, 'E3XZSR');
    expect(find.text('Copied!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('an unpaid booking offers no deposit receipt and is not called confirmed', (tester) async {
    await tester.pumpWidget(_screen(_booking(status: AppointmentStatus.pending, paid: false), _money(paid: false)));
    expect(find.text('Appointment Confirmed!'), findsNothing);
    expect(find.text('Appointment Requested'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('View My Appointments'), 200);
    expect(find.text('Download Deposit Receipt'), findsNothing);
  });
}
