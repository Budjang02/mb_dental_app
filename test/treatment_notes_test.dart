import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/models/patient.dart';
import 'package:mb_dental_app/models/treatment_note.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/screens/records/treatment_notes_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NoteAttribution _who({String attending = '', String legacy = '', String recorder = '', String role = ''}) =>
    NoteAttribution.resolve(
        attendingName: attending, legacyDoctorName: legacy, recorderName: recorder, recordedByRole: role);

TreatmentNote _note({
  String id = 'n1',
  String tooth = '1',
  String condition = 'Root Canal',
  String notes = 'upper',
  NoteAttribution? by,
}) =>
    TreatmentNote(
      id: id,
      // 02:05 UTC → 10:05 AM in Manila.
      createdAt: DateTime.utc(2026, 9, 16, 2, 5),
      toothId: tooth,
      condition: condition,
      notes: notes,
      attribution: by ?? _who(attending: 'Rey Vincent Bolasoc'),
    );

void main() {
  group('attribution follows _trnAttribution', () {
    test('dentist, legacy dentist, no double prefix', () {
      expect(_who(attending: 'Rey Vincent Bolasoc').primary, 'Dr. Rey Vincent Bolasoc');
      expect(_who(legacy: 'Dr. Reyes').primary, 'Dr. Reyes');
      expect(_who(attending: 'Dr Reyes', legacy: 'Other').primary, 'Dr Reyes');
    });

    test('staff-entered with a dentist: one via Staff', () {
      final a = _who(attending: 'Reyes', recorder: 'Ana Cruz', role: 'staff');
      expect(a.primary, 'Dr. Reyes (via Staff)');
      expect(a.staffOnly, isFalse);
    });

    test('staff or admin only: Recorded by, never a doctor', () {
      final staff = _who(recorder: 'Ana Cruz', role: 'staff');
      expect(staff.primary, 'Clinic Staff (Ana Cruz)');
      expect(staff.staffOnly, isTrue);
      expect(_who(recorder: 'Maria', role: 'admin').primary, 'Clinic Admin (Maria)');
      expect(_who(role: 'staff').primary, NoteAttribution.clinicTeam);
    });

    test('old unattributed notes use the clinic fallback', () {
      expect(_who().primary, NoteAttribution.clinic);
      expect(_who(recorder: 'Reyes', role: 'dentist').primary, 'Dr. Reyes');
    });
  });

  test('tooth keys and labels follow _trnToothKey', () {
    expect(TreatmentNote.toothKeyOf('1'), '1');
    expect(TreatmentNote.toothKeyOf('#1'), '1');
    expect(TreatmentNote.toothKeyOf('32'), '32');
    expect(TreatmentNote.toothKeyOf('33'), '');
    expect(TreatmentNote.toothKeyOf('A'), 'P_A');
    expect(TreatmentNote.toothKeyOf('p_a'), 'P_A');
    expect(TreatmentNote.toothKeyOf('U'), '');
    expect(_note(tooth: '#1').toothLabel, '#1');
    expect(_note(tooth: 'A').toothLabel, 'A (primary)');
    expect(_note(tooth: 'A').permanentTooth, isNull);
    expect(_note(tooth: '').toothLabel, 'Not recorded');
  });

  test('date and time in Manila', () {
    expect(_note().dateLabel, 'Sep 16, 2026');
    expect(_note().timeLabel, '10:05 AM');
  });

  test('condition colours and aliases', () {
    expect(ConditionBadgeStyle.of('Root Canal').fill, const Color(0xFFA252EF));
    expect(ConditionBadgeStyle.of('Root Canal').text, Colors.white);
    expect(ConditionBadgeStyle.of('Cavity').fill, ConditionBadgeStyle.of('Caries').fill);
    expect(ConditionBadgeStyle.of('Filling').fill, const Color(0xFF3B82F6));
    expect(ConditionBadgeStyle.of('Other Marked').fill, const Color(0xFF14B8A6));
    expect(ConditionBadgeStyle.of('Missing').dashed, isTrue);
    expect(ConditionBadgeStyle.of('Something new'), same(ConditionBadgeStyle.neutral));
  });

  group('on screen', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
    });
    tearDown(() => PatientRepository().clear());

    testWidgets('list row and popup show the note once, with time and doctor', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      PatientRepository().seedForTest(
        patient: Patient(
            id: 'p', patientCode: 'P', firstName: 'T', lastName: 'P', username: 't', email: 'e', phone: ''),
        treatmentNotes: [_note(notes: 'upper\nsecond line.')],
      );
      String? focused;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TreatmentNotesScreen(onViewOnChart: (k) => focused = k)),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Sep 16, 2026 · 10:05 AM'), findsOneWidget);
      expect(find.text('Tooth #1'), findsOneWidget);
      expect(find.text('Root Canal'), findsOneWidget);
      expect(find.text('Dr. Rey Vincent Bolasoc'), findsOneWidget);

      await tester.tap(find.text('Tooth #1'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Treatment Notes'), findsWidgets);
      expect(find.text('CONDITION'), findsOneWidget);
      expect(find.text('TOOTH NUMBER'), findsOneWidget);
      expect(find.text('DOCTOR'), findsOneWidget);
      // Verbatim, line break included, in the popup's notes panel.
      expect(find.descendant(of: find.byType(Dialog), matching: find.text('upper\nsecond line.')),
          findsOneWidget);

      await tester.tap(find.text('View on Chart'));
      await tester.pumpAndSettle();
      expect(focused, '1');
      expect(find.text('CONDITION'), findsNothing);
    });

    testWidgets('a note with no tooth cannot be sent to the chart; staff-only says Recorded by',
        (tester) async {
      PatientRepository().seedForTest(
        patient: Patient(
            id: 'p', patientCode: 'P', firstName: 'T', lastName: 'P', username: 't', email: 'e', phone: ''),
        treatmentNotes: [_note(tooth: 'Full Mouth', by: _who(recorder: 'Ana Cruz', role: 'staff'))],
      );
      await tester.pumpWidget(const MaterialApp(home: TreatmentNotesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Recorded by Clinic Staff (Ana Cruz)'), findsOneWidget);
      await tester.tap(find.text('Tooth Full Mouth'));
      await tester.pumpAndSettle();
      expect(find.text('RECORDED BY'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'View on Chart'));
      expect(button.onPressed, isNull);
    });
  });
}
