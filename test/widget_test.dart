import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mb_dental_app/app/app.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  // The app reads its Supabase client during the first frame, so the client has
  // to exist before it is pumped. Pointed at a throwaway project: the smoke
  // test only checks that the tree builds, and never issues a request.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Supabase persists its session through shared_preferences, which has no
    // platform channel under test.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DentalApp());
  });
}
