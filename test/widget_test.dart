import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/app/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DentalApp());
  });
}