import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/widgets/schedule_picker.dart';

Widget _picker({DateTime? selectedDate}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SchedulePicker(
            durationMinutes: 60,
            selectedDate: selectedDate,
            selectedStartMinute: null,
            firstDay: DateTime(2026, 10, 1),
            lastDay: DateTime(2026, 12, 31),
            hasOpenSlot: (_) => true,
            slotsFor: (_) => const [],
            onDateSelected: (_) {},
            onSlotSelected: (_) {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('before a date is picked, the time card only asks for one', (tester) async {
    await tester.pumpWidget(_picker());
    expect(find.text('Pick a date'), findsOneWidget);
    expect(find.text('Available start times appear here'), findsOneWidget);
    expect(find.textContaining('Nothing free'), findsNothing);
  });

  testWidgets('the prompt gives way to the times once a date is picked', (tester) async {
    await tester.pumpWidget(_picker(selectedDate: DateTime(2026, 10, 5)));
    expect(find.text('Pick a date'), findsNothing);
    expect(find.text('Available start times appear here'), findsNothing);
  });
}
