import '../models/dental_service.dart';
import '../models/dentist.dart';
import '../repositories/clinic_api.dart';

/// The clinic's reference data — the service menu, the dentist roster and the
/// operating schedule. Every consumer reads through the helpers below, which is
/// what let the service menu move to Supabase without touching the screens.

// --- Specialization credentials ---

const String kGeneralDentistry = 'General Dentistry';
const String kOrthodontics = 'Orthodontics';
const String kEndodontics = 'Endodontics';
const String kProsthodontics = 'Prosthodontics';
const String kOralSurgery = 'Oral Surgery';
const String kCosmeticDentistry = 'Cosmetic Dentistry';

// --- Service menu ---

/// The bookable procedure menu, loaded from the clinic's `procedures` table by
/// [ClinicCatalog]. Empty until that load completes, so the booking wizard
/// shows its loading state rather than a stale hardcoded menu.
List<DentalService> get kDentalServices => ClinicCatalog().services;

/// The menu grouped for Step 1, in the order the clinic lists its service
/// lines. Groups with nothing active in them are left out rather than shown
/// empty.
Map<ServiceGroup, List<DentalService>> get servicesByCategory => {
      for (final group in ClinicCatalog().groups)
        if (kDentalServices.any((s) => s.categoryId == group.code))
          group: kDentalServices.where((s) => s.categoryId == group.code).toList(),
    };

DentalService? serviceById(String id) {
  for (final service in kDentalServices) {
    if (service.id == id) return service;
  }
  return null;
}

// --- Dentist roster ---

const List<Dentist> kDentists = [
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

/// Dentists credentialed for **every** selected service. An empty selection
/// returns the whole roster.
List<Dentist> eligibleDentists(Iterable<DentalService> services) {
  if (services.isEmpty) return List.unmodifiable(kDentists);
  return kDentists.where((d) => d.canPerformAll(services)).toList();
}

/// The credentials a selection demands, for the "why is this list short?"
/// explainer in Step 2.
Set<String> requiredSpecializations(Iterable<DentalService> services) =>
    services.map((s) => s.requiredSpecialization).toSet();

/// The dentist the clinic would staff a visit with: credentialed for every
/// selected procedure *and* holding clinic on that weekday. This is what the
/// booking summary names, standing in for the assignment a real backend would
/// make when the request lands.
///
/// Returns null when nobody on the roster covers the selection that day — the
/// summary then says the dentist is still to be assigned rather than naming
/// someone who is not actually in.
Dentist? assignedDentistFor(Iterable<DentalService> services, DateTime day) {
  if (services.isEmpty) return null;
  for (final dentist in eligibleDentists(services)) {
    if (dentist.clinicDays.contains(day.weekday)) return dentist;
  }
  return null;
}

Dentist? dentistByName(String name) {
  for (final dentist in kDentists) {
    if (dentist.name == name) return dentist;
  }
  return null;
}

// --- Operating schedule ---

/// The clinic is open Wednesday through Sunday; Monday and Tuesday are closed.
const Set<int> kClinicOperatingDays = {
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
  DateTime.saturday,
  DateTime.sunday,
};

/// Minutes from midnight. Chairs open at 10:00 AM and the last procedure must
/// finish by 4:00 PM.
const int kClinicOpenMinute = 10 * 60;
const int kClinicCloseMinute = 16 * 60;

/// Bookings start on a 15-minute grid.
const int kSlotStepMinutes = 15;

/// The three stretches of the clinic day the slot picker files start times
/// under. They tile the whole 10:00 AM - 4:00 PM window with no gaps, so every
/// bookable start belongs to exactly one band.
enum TimeOfDayBand { morning, afternoon, lateAfternoon }

extension TimeOfDayBandX on TimeOfDayBand {
  String get label {
    switch (this) {
      case TimeOfDayBand.morning:
        return 'Morning';
      case TimeOfDayBand.afternoon:
        return 'Afternoon';
      case TimeOfDayBand.lateAfternoon:
        return 'Late Afternoon';
    }
  }

  /// First start time this band accepts, in minutes from midnight.
  int get startMinute {
    switch (this) {
      case TimeOfDayBand.morning:
        return 10 * 60;
      case TimeOfDayBand.afternoon:
        return 12 * 60;
      case TimeOfDayBand.lateAfternoon:
        return 14 * 60;
    }
  }

  /// Last start time this band accepts, inclusive.
  ///
  /// The bands read as 10-12, 12-2 and 2-4, so each one ends a quarter-hour
  /// before the next begins — 11:45 is the last morning start because 12:00
  /// is the first afternoon one. Late Afternoon is bounded at the 4:00 PM
  /// close: nothing can actually start then, but stopping short would leave a
  /// dead quarter-hour belonging to no band.
  int get endMinute {
    switch (this) {
      case TimeOfDayBand.morning:
        return 11 * 60 + 45;
      case TimeOfDayBand.afternoon:
        return 13 * 60 + 45;
      case TimeOfDayBand.lateAfternoon:
        return 16 * 60;
    }
  }

  bool contains(int minuteOfDay) =>
      minuteOfDay >= startMinute && minuteOfDay <= endMinute;

  /// "10:00 AM - 11:45 AM", for the tooltip under the filter toolbar.
  String get windowLabel =>
      '${formatMinuteOfDay(startMinute)} \u2013 ${formatMinuteOfDay(endMinute)}';
}

/// The band a start time falls in, or null if it is outside clinic hours.
TimeOfDayBand? bandFor(int minuteOfDay) {
  for (final band in TimeOfDayBand.values) {
    if (band.contains(minuteOfDay)) return band;
  }
  return null;
}

bool isClinicOpenOn(DateTime day) => kClinicOperatingDays.contains(day.weekday);

const List<String> _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String weekdayLabel(int weekday) => _weekdayNames[weekday - 1];

/// "Wed – Sun" style summary of the operating week.
String get clinicOperatingDaysLabel {
  final days = kClinicOperatingDays.toList()..sort();
  return '${weekdayLabel(days.first)} – ${weekdayLabel(days.last)}';
}

String get clinicHoursLabel =>
    '${formatMinuteOfDay(kClinicOpenMinute)} – ${formatMinuteOfDay(kClinicCloseMinute)}';

/// Every 15-minute start on [day] that leaves room for a [durationMinutes]
/// block before closing. Empty on a day the clinic is closed.
List<int> slotStartsFor(DateTime day, int durationMinutes) {
  if (!isClinicOpenOn(day) || durationMinutes <= 0) return const [];
  final starts = <int>[];
  for (var minute = kClinicOpenMinute;
      minute + durationMinutes <= kClinicCloseMinute;
      minute += kSlotStepMinutes) {
    starts.add(minute);
  }
  return starts;
}

/// Formats minutes-from-midnight as the `hh:mm AM` label used on chips and
/// stored on appointments.
String formatMinuteOfDay(int minuteOfDay) {
  final hour24 = minuteOfDay ~/ 60;
  final minute = minuteOfDay % 60;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  var hour12 = hour24 % 12;
  if (hour12 == 0) hour12 = 12;
  return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
}

/// Inverse of [formatMinuteOfDay]. Returns null for anything unparseable, so
/// legacy or hand-entered slot strings degrade instead of throwing.
int? parseMinuteOfDay(String timeSlot) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})\s*([AaPp])').firstMatch(timeSlot.trim());
  if (match == null) return null;
  var hour = int.parse(match.group(1)!) % 12;
  final minute = int.parse(match.group(2)!);
  if (match.group(3)!.toLowerCase() == 'p') hour += 12;
  return hour * 60 + minute;
}

// --- Clinic contact details (Profile → Support) ---

/// The clinic's own contact card, read from the `clinics` table. Hardcoding
/// these sent patients to an address the clinic had already moved from, so the
/// only fallback is the name.
String get kClinicName => ClinicCatalog().clinic.name;
String get kClinicPhone => ClinicCatalog().clinic.phone;
String get kClinicAddress => ClinicCatalog().clinic.address;

/// The clinic publishes no email address, so support routes through the phone
/// number and the in-app chat instead.
const String kClinicEmail = '';
