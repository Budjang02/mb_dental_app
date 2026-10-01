import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/screens/auth/forgot_password_screen.dart';
import 'package:mb_dental_app/screens/auth/register_screen.dart';
import 'package:mb_dental_app/widgets/auth_widgets.dart';

Future<void> _pump(WidgetTester tester, Widget screen, Size size, {double keyboard = 0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pump();
}

void main() {
  testWidgets('Create Account terms stay at the bottom and never ride the keyboard',
      (tester) async {
    for (final size in const [Size(320, 568), Size(375, 812), Size(430, 932)]) {
      // Keyboard closed: the notice sits at the bottom of the screen, or just
      // below the form on a phone too short to show both at once.
      await _pump(tester, const RegisterScreen(), size);
      expect(tester.takeException(), isNull);
      final closed = tester.getRect(find.byType(TermsNotice));
      expect(closed.bottom, greaterThan(size.height - 60));
      if (size.height >= 800) expect(closed.bottom, lessThanOrEqualTo(size.height));

      // Keyboard open: the notice does not move up to sit on top of it.
      final keyboard = size.height * 0.4;
      await _pump(tester, const RegisterScreen(), size, keyboard: keyboard);
      expect(tester.takeException(), isNull);
      final open = tester.getRect(find.byType(TermsNotice));
      expect(open.top, greaterThanOrEqualTo(size.height - keyboard));

      // And the form still scrolls down to reach it.
      await tester.scrollUntilVisible(find.byType(TermsNotice), 100,
          scrollable: find.byType(Scrollable).first);
      expect(tester.getRect(find.byType(TermsNotice)).bottom,
          lessThanOrEqualTo(size.height - keyboard));
    }
  });

  testWidgets('Terms link opens the bundled Terms and Conditions text', (tester) async {
    await _pump(tester, const Scaffold(body: Center(child: TermsNotice(leadIn: 'By signing up you agree to our'))),
        const Size(375, 812));

    final notice = find.byType(TermsNotice);
    // Tap the start of the second line, where "and Conditions of Use" is.
    final rect = tester.getRect(notice);
    await tester.tapAt(Offset(rect.center.dx + 30, rect.bottom - 6));
    await tester.pumpAndSettle();

    expect(find.text('TERMS AND CONDITIONS'), findsOneWidget);
    expect(find.text('AGREEMENT TO OUR LEGAL TERMS'), findsOneWidget);
    expect(find.textContaining('not published in the app'), findsNothing);
  });

  testWidgets('Forgot Password has no lock badge above the heading', (tester) async {
    await _pump(tester, const ForgotPasswordScreen(), const Size(375, 812));

    expect(find.byIcon(CupertinoIcons.lock_rotation), findsNothing);
    final heading = tester.getRect(find.text('Forgot Password'));
    // Directly under the app bar now.
    expect(heading.top, lessThan(kToolbarHeight + 24));
  });
}
