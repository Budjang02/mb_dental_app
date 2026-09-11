import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/models/patient.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/record_load_gate.dart';
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
        for (int i = 0; i < 40; i++)
          SizedBox(height: 60, child: Text('row $i')),
      ],
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  // The gate asks Supabase whether anyone is signed in, so the client has to
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

  group('RecordLoadGate', () {
    testWidgets('shows the page and lets it scroll once the record has loaded',
        (tester) async {
      PatientRepository().seedForTest(patient: _patient());
      await tester.pumpWidget(_wrap(RecordLoadGate(child: _tallPage())));
      await tester.pump();

      expect(find.text('row 0'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      // The first row has scrolled away, which is the whole point.
      expect(find.text('row 0'), findsNothing);
    });

    testWidgets('keeps the waiting state scrollable so the screen never locks up',
        (tester) async {
      await tester.pumpWidget(_wrap(RecordLoadGate(child: _tallPage())));
      await tester.pump();

      expect(find.text('row 0'), findsNothing);

      final scrollable = find.byType(Scrollable);
      expect(scrollable, findsOneWidget);

      // A drag on the waiting state must be accepted rather than ignored,
      // which is what makes pull-to-refresh reachable from here.
      await tester.drag(scrollable, const Offset(0, 200));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('puts pull-to-refresh on the waiting state', (tester) async {
      await tester.pumpWidget(_wrap(RecordLoadGate(child: _tallPage())));
      // `pump`, not `pumpAndSettle`: the waiting state animates a spinner
      // forever, so settling never happens.
      await tester.pump();

      // Nobody is signed in under test, so the gate stays waiting rather than
      // firing a request at Supabase — and stays refreshable while it waits.
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });
  });
}
