import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/data/clinic_catalog.dart';
import 'package:mb_dental_app/models/dental_service.dart';
import 'package:mb_dental_app/models/dentist.dart';
import 'package:mb_dental_app/repositories/clinic_api.dart';

DentalService _service(String id, {String code = 'general'}) => DentalService(
      id: id,
      name: id,
      description: '',
      specializationCode: code,
      categoryId: 'other',
      durationMinutes: 30,
      price: 0,
      requiredSpecialization: credentialForSpecializationCode(code),
    );

/// The schedule as the clinic keeps it in `clinic_settings` and
/// `clinic_closures`: open 9-5, closed Mondays and Tuesdays, closed on
/// Christmas, and closed over lunch on one Thursday.
final ClinicSchedule _schedule = ClinicSchedule(
  openMinute: 9 * 60,
  closeMinute: 17 * 60,
  closures: [
    const ClinicClosure(weekday: DateTime.monday),
    const ClinicClosure(weekday: DateTime.tuesday),
    ClinicClosure(date: DateTime(2026, 12, 25)),
    ClinicClosure(date: DateTime(2026, 9, 17), startMinute: 12 * 60, endMinute: 13 * 60),
  ],
);

void main() {
  tearDown(() => ClinicCatalog().seedForTest(const []));

  group('clinic schedule', () {
    test('before it loads, the built-in week stands', () {
      expect(clinicOperatingDays, kClinicOperatingDays);
      expect(clinicOpenMinute, kClinicOpenMinute);
      expect(clinicCloseMinute, kClinicCloseMinute);
    });

    test('recurring all-day closures decide the operating week', () {
      ClinicCatalog().seedForTest(const [], schedule: _schedule);
      expect(clinicOperatingDays, {
        DateTime.wednesday,
        DateTime.thursday,
        DateTime.friday,
        DateTime.saturday,
        DateTime.sunday,
      });
      // 2026-09-14 is a Monday.
      expect(isClinicOpenOn(DateTime(2026, 9, 14)), isFalse);
      expect(isClinicOpenOn(DateTime(2026, 9, 16)), isTrue);
    });

    test('a dated holiday closes that day only', () {
      ClinicCatalog().seedForTest(const [], schedule: _schedule);
      // 2026-12-25 is a Friday, an operating weekday.
      expect(DateTime(2026, 12, 25).weekday, DateTime.friday);
      expect(isClinicOpenOn(DateTime(2026, 12, 25)), isFalse);
      expect(isClinicOpenOn(DateTime(2026, 12, 26)), isTrue);
      expect(slotStartsFor(DateTime(2026, 12, 25), 30), isEmpty);
    });

    test('opening hours come from clinic_settings', () {
      ClinicCatalog().seedForTest(const [], schedule: _schedule);
      final starts = slotStartsFor(DateTime(2026, 9, 16), 30);
      expect(starts.first, 9 * 60);
      expect(starts.last + 30, 17 * 60);
      expect(clinicHoursLabel, '09:00 AM – 05:00 PM');
    });

    test('a partial closure removes only the starts that overlap it', () {
      ClinicCatalog().seedForTest(const [], schedule: _schedule);
      final thursday = DateTime(2026, 9, 17);
      final starts = slotStartsFor(thursday, 60);
      // An hour-long visit may end exactly as lunch starts, or start as it ends.
      expect(starts, contains(11 * 60));
      expect(starts, contains(13 * 60));
      expect(starts, isNot(contains(11 * 60 + 15)));
      expect(starts, isNot(contains(12 * 60 + 45)));
      // Only that Thursday: the next one keeps its lunch slots.
      expect(slotStartsFor(DateTime(2026, 9, 24), 60), contains(12 * 60));
    });
  });

  group('dentist hours', () {
    const hours = {
      DateTime.thursday: [
        DoctorHours(startMinute: 10 * 60, endMinute: 15 * 60, breakStartMinute: 12 * 60, breakEndMinute: 13 * 60),
      ],
    };

    test('a visit gets a dentist only inside their hours and clear of their break', () {
      ClinicCatalog().seedForTest(
        const [],
        schedule: _schedule,
        doctors: const [
          Dentist(
            id: 'd',
            name: 'Dr. Hours',
            title: 'General Dentist',
            specializations: {kGeneralDentistry},
            specializationCodes: {'general'},
            clinicDays: {DateTime.thursday},
            hoursByWeekday: hours,
          ),
        ],
      );
      // 2026-09-24 is a Thursday with no closures.
      final thursday = DateTime(2026, 9, 24);
      final checkup = [_service('checkup')];

      expect(assignedDentistFor(checkup, thursday, startMinute: 10 * 60, durationMinutes: 60)?.name, 'Dr. Hours');
      // 11:30-12:30 runs into the 12-1 break.
      expect(assignedDentistFor(checkup, thursday, startMinute: 11 * 60 + 30, durationMinutes: 60), isNull);
      // Ends exactly as the break starts / starts exactly as it ends.
      expect(assignedDentistFor(checkup, thursday, startMinute: 11 * 60, durationMinutes: 60)?.name, 'Dr. Hours');
      expect(assignedDentistFor(checkup, thursday, startMinute: 13 * 60, durationMinutes: 60)?.name, 'Dr. Hours');
      // 2:30-3:30 runs past 3 PM.
      expect(assignedDentistFor(checkup, thursday, startMinute: 14 * 60 + 30, durationMinutes: 60), isNull);
    });

    test('with no hours on record, being in that day is enough', () {
      const dentist = Dentist(
        id: 'd',
        name: 'Dr. Days',
        title: 'General Dentist',
        specializations: {kGeneralDentistry},
        specializationCodes: {'general'},
        clinicDays: {DateTime.thursday},
      );
      expect(dentist.isAvailableAt(DateTime(2026, 9, 24), 8 * 60, 9 * 60), isTrue);
      expect(dentist.isAvailableAt(DateTime(2026, 9, 23), 10 * 60, 11 * 60), isFalse);
    });
  });

  group('clinic roster', () {
    test("the clinic's procedure assignments outrank specialization codes", () {
      const dentist = Dentist(
        id: 'd',
        name: 'Dr. Assigned',
        title: 'Dentist',
        specializations: {kGeneralDentistry},
        specializationCodes: {'general'},
        procedureIds: {'cleaning'},
        clinicDays: {DateTime.thursday},
      );
      expect(dentist.canPerform(_service('cleaning')), isTrue);
      // Same code, but the clinic has not assigned this procedure to them.
      expect(dentist.canPerform(_service('whitening')), isFalse);
    });

    test('a day off keeps the dentist from being assigned that day only', () {
      ClinicCatalog().seedForTest(
        const [],
        schedule: _schedule,
        doctors: [
          Dentist(
            id: 'd',
            name: 'Dr. Thursday',
            title: 'Dentist',
            specializations: const {kGeneralDentistry},
            specializationCodes: const {'general'},
            clinicDays: const {DateTime.thursday},
            offDates: {DateTime(2026, 9, 17)},
          ),
        ],
      );
      final checkup = [_service('checkup')];
      expect(assignedDentistFor(checkup, DateTime(2026, 9, 17)), isNull);
      expect(assignedDentistFor(checkup, DateTime(2026, 9, 24))?.name, 'Dr. Thursday');
    });

    test('nobody is assigned on a day the clinic is closed', () {
      ClinicCatalog().seedForTest(
        const [],
        schedule: _schedule,
        doctors: const [
          Dentist(
            id: 'd',
            name: 'Dr. Friday',
            title: 'Dentist',
            specializations: {kGeneralDentistry},
            specializationCodes: {'general'},
            clinicDays: {DateTime.friday},
          ),
        ],
      );
      expect(assignedDentistFor([_service('checkup')], DateTime(2026, 12, 25)), isNull);
      expect(assignedDentistFor([_service('checkup')], DateTime(2027, 1, 1)), isNotNull);
    });
  });
}
