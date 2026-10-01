import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/screens/auth/otp_verification_screen.dart';

Future<void> _pump(WidgetTester tester, Size size, {double keyboard = 0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(home: OtpVerificationScreen(destination: 'patient@gmail.com')),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows heading, email and six empty boxes', (tester) async {
    await _pump(tester, const Size(375, 812));

    expect(find.text('Enter 6-digit code'), findsOneWidget);
    expect(find.textContaining('patient@gmail.com', findRichText: true), findsOneWidget);
    expect(find.byType(AnimatedContainer), findsNWidgets(6));
    expect(find.text('-'), findsNothing);
  });

  testWidgets('accepts digits only and caps at six, as when pasting', (tester) async {
    await _pump(tester, const Size(375, 812));

    await tester.enterText(find.byType(TextField), 'Code: 12a3 4567 89');
    await tester.pump();

    for (final d in ['1', '2', '3', '4', '5', '6']) {
      expect(find.text(d), findsOneWidget);
    }
    expect(find.text('7'), findsNothing);
  });

  testWidgets('resend countdown ticks every second, then enables', (tester) async {
    await _pump(tester, const Size(375, 812));

    expect(find.text('Resend code (60s)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend code (59s)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 36));
    expect(find.text('Resend code (23s)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 23));
    expect(find.text('Resend code'), findsOneWidget);
  });

  testWidgets('Continue sits at the bottom and nothing overflows with keyboard',
      (tester) async {
    for (final size in const [Size(320, 568), Size(375, 812), Size(430, 932)]) {
      await _pump(tester, size, keyboard: size.height * 0.4);
      expect(tester.takeException(), isNull);
      final button = tester.getRect(find.widgetWithText(ElevatedButton, 'Continue'));
      expect(button.bottom, lessThanOrEqualTo(size.height * 0.6));
      expect(button.bottom, greaterThan(size.height * 0.6 - 80));
      expect(button.height, 50);
    }
  });
}
