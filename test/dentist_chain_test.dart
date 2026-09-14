import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/data/clinic_catalog.dart';
import 'package:mb_dental_app/models/dental_service.dart';
import 'package:mb_dental_app/models/dentist.dart';
import 'package:mb_dental_app/repositories/clinic_api.dart';

/// A roster as the clinic keeps it. The app has no built-in doctors any more,
/// so every chain below runs against a roster seeded the way
/// `patient_doctor_roster()` would deliver it.
const List<Dentist> _roster = [
  Dentist(
    id: 'doc-bolasoc',
    name: 'Dr. Rey Vincent Bolasoc',
    title: 'General Dentist · Endodontist',
    specializations: {kGeneralDentistry, kEndodontics, kOralSurgery},
    clinicDays: {DateTime.wednesday, DateTime.thursday, DateTime.friday, DateTime.saturday},
  ),
  Dentist(
    id: 'doc-jenneline',
    name: 'Dr. Jenneline Mariano',
    title: 'General Dentist · Prosthodontist',
    specializations: {kGeneralDentistry, kProsthodontics, kCosmeticDentistry},
    clinicDays: {DateTime.wednesday, DateTime.friday, DateTime.saturday, DateTime.sunday},
  ),
  Dentist(
    id: 'doc-johnpaul',
    name: 'Dr. John Paul Mariano',
    title: 'Orthodontist',
    specializations: {kOrthodontics, kGeneralDentistry},
    clinicDays: {DateTime.thursday, DateTime.saturday, DateTime.sunday},
  ),
  Dentist(
    id: 'doc-cruz',
    name: 'Dr. Ana Marie Cruz',
    title: 'Cosmetic Dentist',
    specializations: {kCosmeticDentistry, kGeneralDentistry},
    clinicDays: {DateTime.wednesday, DateTime.thursday, DateTime.sunday},
  ),
];

/// The booking chain is procedures → credential → dentist → clinic day. These
/// tests hold each link: a credential the clinic's menu demands must be carried
/// by someone on the roster, and that someone must actually hold clinic on the
/// days the wizard offers.
void main() {
  setUp(() => ClinicCatalog().seedForTest(const [], doctors: _roster));
  tearDown(() => ClinicCatalog().seedForTest(const []));

  DentalService service(String credential, {String id = 's'}) => DentalService(
        id: id,
        name: id,
        description: '',
        specializationCode: 'general',
        categoryId: 'other',
        durationMinutes: 30,
        price: 0,
        requiredSpecialization: credential,
      );

  const credentials = [
    kGeneralDentistry,
    kOrthodontics,
    kProsthodontics,
    kOralSurgery,
    kCosmeticDentistry,
  ];

  group('credential to dentist', () {
    for (final credential in credentials) {
      test('$credential is carried by someone on the roster', () {
        expect(eligibleDentists([service(credential)]), isNotEmpty);
      });

      test('$credential has at least one clinic day', () {
        expect(eligibleClinicDays([service(credential)]), isNotEmpty);
      });
    }
  });

  group('dentist to clinic day', () {
    test('no credential is bookable on a day the clinic is shut', () {
      // 2026-09-14 is a Monday; the clinic opens Wednesday to Sunday.
      final monday = DateTime(2026, 9, 14);
      expect(monday.weekday, DateTime.monday);
      for (final credential in credentials) {
        expect(hasEligibleDentistOn([service(credential)], monday), isFalse,
            reason: credential);
      }
    });

    test('every offered day resolves to a named dentist', () {
      for (final credential in credentials) {
        for (final weekday in eligibleClinicDays([service(credential)])) {
          final day = DateTime(2026, 9, 14).add(Duration(days: weekday - 1));
          expect(day.weekday, weekday);
          expect(assignedDentistFor([service(credential)], day), isNotNull,
              reason: '$credential on ${weekdayLabel(weekday)}');
        }
      }
    });

    test('only clinic operating days are ever offered', () {
      for (final credential in credentials) {
        for (final weekday in eligibleClinicDays([service(credential)])) {
          expect(kClinicOperatingDays.contains(weekday), isTrue, reason: credential);
        }
      }
    });
  });

  group('mixed selections', () {
    test('a mix one dentist covers stays bookable', () {
      final mix = [
        service(kGeneralDentistry, id: 'a'),
        service(kOralSurgery, id: 'b'),
      ];
      expect(eligibleDentists(mix), isNotEmpty);
      expect(eligibleClinicDays(mix), isNotEmpty);
    });

    test('a mix nobody covers is unbookable rather than unassigned', () {
      final mix = [
        service(kOrthodontics, id: 'a'),
        service(kOralSurgery, id: 'b'),
      ];
      expect(eligibleDentists(mix), isEmpty);
      expect(eligibleClinicDays(mix), isEmpty);
      for (var weekday = 1; weekday <= 7; weekday++) {
        final day = DateTime(2026, 9, 14).add(Duration(days: weekday - 1));
        expect(hasEligibleDentistOn(mix, day), isFalse);
      }
    });
  });

  group('no roster', () {
    test('an empty roster offers no dentist and no day, never invented ones', () {
      ClinicCatalog().seedForTest(const []);
      expect(hasClinicRoster, isFalse);
      expect(kDentists, isEmpty);
      expect(eligibleDentists([service(kGeneralDentistry)]), isEmpty);
      expect(eligibleClinicDays([service(kGeneralDentistry)]), isEmpty);
      expect(assignedDentistFor([service(kGeneralDentistry)], DateTime(2026, 9, 16)), isNull);
    });

    test('a failed roster load is told apart from an empty one', () {
      ClinicCatalog().seedForTest(const [], rosterFailed: true);
      expect(ClinicCatalog().rosterFailed, isTrue);
      ClinicCatalog().seedForTest(const []);
      expect(ClinicCatalog().rosterFailed, isFalse);
    });
  });

  group('specialization label', () {
    test('a rostered doctor announces their own title', () {
      expect(doctorSpecializationLabel('Dr. John Paul Mariano'), 'Orthodontist');
    });

    test('the honorific is not part of the match', () {
      expect(doctorSpecializationLabel('John Paul Mariano'), 'Orthodontist');
      expect(doctorSpecializationLabel('  dr.  John Paul  Mariano '), 'Orthodontist');
      expect(dentistByName('Rey Vincent Bolasoc')?.title,
          'General Dentist · Endodontist');
    });

    test('an unassigned booking still announces something', () {
      expect(doctorSpecializationLabel(null), isNotEmpty);
      expect(doctorSpecializationLabel(''), isNotEmpty);
      expect(doctorSpecializationLabel('Someone Off Roster'), isNotEmpty);
    });
  });
}
