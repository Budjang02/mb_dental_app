import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/screens/appointments/book_appointment_screen.dart';

void main() {
  // Each test loads the files fresh; a cached load from the previous test
  // belongs to that test's clock and never completes in this one.
  setUp(() => rootBundle.clear());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: BookingTermsScreen()));
    // The text files load on a real clock; pump until they are on screen.
    for (var i = 0; i < 50 && find.byType(ListView).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pump();
  }

  ElevatedButton agree(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'AGREE & CONTINUE'));

  testWidgets('shows the Terms and the Privacy Policy as one text', (tester) async {
    await open(tester);
    expect(find.text('TERMS AND CONDITIONS'), findsOneWidget);
    // The Privacy Policy follows in the same scroll, not on a tab of its own.
    await tester.scrollUntilVisible(
      find.text('SUMMARY OF KEY POINTS'),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 1000,
    );
    expect(find.text('SUMMARY OF KEY POINTS'), findsOneWidget);
    expect(find.byType(Tab), findsNothing);
  });

  testWidgets('AGREE & CONTINUE is locked until the patient scrolls to the end', (tester) async {
    await open(tester);
    expect(find.text('Legal Terms & Privacy Policy'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(agree(tester).onPressed, isNull);

    // Part-way down is not enough.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(agree(tester).onPressed, isNull);

    // To the bottom.
    for (var i = 0; i < 200 && agree(tester).onPressed == null; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
    }
    expect(agree(tester).onPressed, isNotNull);
  });
}
