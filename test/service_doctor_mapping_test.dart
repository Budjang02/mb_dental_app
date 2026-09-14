import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/data/clinic_catalog.dart';
import 'package:mb_dental_app/models/dental_service.dart';
import 'package:mb_dental_app/models/dentist.dart';
import 'package:mb_dental_app/repositories/clinic_api.dart';

/// A procedure as the clinic's `procedures` row maps into the app:
/// [specializationCode] is the column the doctor mapping runs on.
DentalService _service(String name, String code) => DentalService(
      id: name,
      name: name,
      description: '',
      specializationCode: code,
      categoryId: 'other',
      durationMinutes: 30,
      price: 0,
      requiredSpecialization: credentialForSpecializationCode(code),
    );

/// A dentist as `patient_doctor_roster()` returns one: codes, not credential
/// labels.
Dentist _doctor(
  String name,
  Set<String> codes, {
  Set<int> clinicDays = const {DateTime.wednesday, DateTime.thursday},
}) =>
    Dentist(
      id: name,
      name: name,
      title: 'Dentist',
      specializations: {for (final code in codes) credentialForSpecializationCode(code)},
      specializationCodes: codes,
      clinicDays: clinicDays,
    );

void main() {
  tearDown(() => ClinicCatalog().seedForTest(const []));

  group('service to doctor mapping', () {
    test('a service resolves to the doctors holding its specialization', () {
      ClinicCatalog().seedForTest(
        [_service('Metal Braces', 'ortho'), _service('Dental Checkup', 'general')],
        doctors: [
          _doctor('Dr. Ortho', {'ortho', 'general'}),
          _doctor('Dr. General', {'general'}),
          _doctor('Dr. Surgeon', {'surgery', 'general'}),
        ],
      );

      final braces = doctorsForService(_service('Metal Braces', 'ortho'));
      expect(braces.map((d) => d.name), ['Dr. Ortho']);

      final checkup = doctorsForService(_service('Dental Checkup', 'general'));
      expect(checkup.map((d) => d.name), ['Dr. Ortho', 'Dr. General', 'Dr. Surgeon']);
    });

    test('a specialization nobody holds resolves to no doctor', () {
      ClinicCatalog().seedForTest(
        [_service('TMJ Evaluation', 'tmj')],
        doctors: [_doctor('Dr. General', {'general'})],
      );

      expect(doctorsForService(_service('TMJ Evaluation', 'tmj')), isEmpty);
      expect(eligibleClinicDays([_service('TMJ Evaluation', 'tmj')]), isEmpty);
    });

    test('a mix needs one doctor holding every code, not one each', () {
      ClinicCatalog().seedForTest(
        const [],
        doctors: [
          _doctor('Dr. Ortho', {'ortho'}),
          _doctor('Dr. Surgeon', {'surgery'}),
          _doctor('Dr. Both', {'ortho', 'surgery'}),
        ],
      );

      final mix = [_service('Braces', 'ortho'), _service('Extraction', 'surgery')];
      expect(eligibleDentists(mix).map((d) => d.name), ['Dr. Both']);
    });

    test('with no roster there are no dentists, and none are invented', () {
      expect(hasClinicRoster, isFalse);
      expect(kDentists, isEmpty);
      expect(doctorsForService(_service('Dental Checkup', 'general')), isEmpty);

      ClinicCatalog().seedForTest(const [], doctors: [_doctor('Dr. Only', {'general'})]);

      expect(hasClinicRoster, isTrue);
      expect(kDentists.map((d) => d.name), ['Dr. Only']);
    });

    test('clinic days come from the roster, not from the whole opening week', () {
      ClinicCatalog().seedForTest(
        const [],
        doctors: [
          _doctor('Dr. Ortho', {'ortho'}, clinicDays: {DateTime.thursday, DateTime.sunday}),
        ],
      );

      final braces = [_service('Braces', 'ortho')];
      expect(eligibleClinicDays(braces), [DateTime.thursday, DateTime.sunday]);

      // 2026-09-16 is a Wednesday: the clinic is open, this dentist is not in.
      final wednesday = DateTime(2026, 9, 16);
      expect(wednesday.weekday, DateTime.wednesday);
      expect(hasEligibleDentistOn(braces, wednesday), isFalse);
      expect(hasEligibleDentistOn(braces, DateTime(2026, 9, 17)), isTrue);
    });
  });

  group('specialization labels', () {
    test("the clinic's own label wins over the built-in credential name", () {
      ClinicCatalog().seedForTest(
        const [],
        specializationLabels: {'ortho': 'Braces and Aligners'},
      );

      expect(specializationLabelFor('ortho'), 'Braces and Aligners');
      // Not seeded, so the built-in name stands in.
      expect(specializationLabelFor('surgery'), kOralSurgery);
    });

    test('codes are matched past case and padding', () {
      ClinicCatalog().seedForTest(const [], specializationLabels: {'endo': 'Root Canals'});
      expect(specializationLabelFor('  ENDO '), 'Root Canals');
    });

    test('an unknown code falls back to general dentistry', () {
      expect(specializationLabelFor('something-new'), kGeneralDentistry);
      expect(credentialForSpecializationCode(''), kGeneralDentistry);
    });
  });

  group('matching without clinic codes', () {
    test('a dentist with no codes still matches on credential labels', () {
      const orthodontist = Dentist(
        id: 'ortho',
        name: 'Dr. Ortho',
        title: 'Orthodontist',
        specializations: {kOrthodontics, kGeneralDentistry},
        clinicDays: {DateTime.thursday},
      );
      expect(orthodontist.specializationCodes, isEmpty);
      expect(orthodontist.canPerform(_service('Braces', 'ortho')), isTrue);
      expect(orthodontist.canPerform(_service('Surgical Extraction', 'surgery')), isFalse);
    });
  });
}
