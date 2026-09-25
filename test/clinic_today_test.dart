import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/data/clinic_catalog.dart';

void main() {
  test('today is counted on the Manila calendar, whatever the phone zone', () {
    final manila = DateTime.now().toUtc().add(const Duration(hours: 8));
    expect(clinicToday(), DateTime(manila.year, manila.month, manila.day));
  });

  test('patients can book from tomorrow in Manila, never today', () {
    expect(firstPatientBookableDay, clinicToday().add(const Duration(days: 1)));
  });
}
