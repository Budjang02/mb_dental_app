import '../app/messages.dart';
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
///
/// When the menu came from `booking_catalogue()`, each group lists its
/// services exactly as that RPC returned them — the order the website shows —
/// and a service filed under two categories appears under both.
Map<ServiceGroup, List<DentalService>> get servicesByCategory {
  final byGroup = ClinicCatalog().servicesByGroup;
  if (byGroup.isNotEmpty) {
    return {
      for (final group in ClinicCatalog().groups)
        if ((byGroup[group.code] ?? const <DentalService>[]).isNotEmpty)
          group: byGroup[group.code]!,
    };
  }
  return {
    for (final group in ClinicCatalog().groups)
      if (kDentalServices.any((s) => s.categoryId == group.code))
        group: kDentalServices.where((s) => s.categoryId == group.code).toList(),
  };
}

DentalService? serviceById(String id) {
  for (final service in kDentalServices) {
    if (service.id == id) return service;
  }
  return null;
}

// --- Dentist roster ---

/// The dentist roster the app books against: the clinic's own, read through
/// `patient_doctor_roster()` by [ClinicApi.loadDoctors]. There is no built-in
/// stand-in. Like the website, an empty or failed roster shows a real empty
/// state that says why, never invented names.
List<Dentist> get kDentists => ClinicCatalog().doctors;

/// True once the clinic's roster has loaded with at least one dentist.
bool get hasClinicRoster => ClinicCatalog().doctors.isNotEmpty;

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
///
/// With [startMinute], the dentist must also be working for the whole visit
/// ([durationMinutes] from that start) and clear of their break — so a booked
/// time always has a named dentist behind it.
Dentist? assignedDentistFor(
  Iterable<DentalService> services,
  DateTime day, {
  int? startMinute,
  int durationMinutes = 0,
}) {
  if (services.isEmpty) return null;
  if (!isClinicOpenOn(day)) return null;
  for (final dentist in eligibleDentists(services)) {
    if (!dentist.isInOn(day)) continue;
    if (startMinute != null &&
        !dentist.isAvailableAt(day, startMinute, startMinute + durationMinutes)) {
      continue;
    }
    return dentist;
  }
  return null;
}

/// The clinic's label for a specialization code, falling back to the built-in
/// credential name. This is what a service announces as the credential it needs.
String specializationLabelFor(String code) {
  final normalised = code.trim().toLowerCase();
  final fromClinic = ClinicCatalog().specializationLabels[normalised];
  if (fromClinic != null && fromClinic.isNotEmpty) return fromClinic;
  return credentialForSpecializationCode(normalised);
}

/// The built-in credential name for a clinic specialization code. Mirrors
/// `ClinicApi._credentialFrom`, which maps the same codes when it builds the
/// service menu.
String credentialForSpecializationCode(String code) {
  switch (code.trim().toLowerCase()) {
    case 'ortho':
    case 'tmj':
      return kOrthodontics;
    case 'endo':
      return kEndodontics;
    case 'restorative':
      return kProsthodontics;
    case 'surgery':
      return kOralSurgery;
    case 'esthetics':
      return kCosmeticDentistry;
    default:
      return kGeneralDentistry;
  }
}

/// The doctors who may perform [service] — the roster filtered to the
/// specialization the service carries. This is what the app shows when a
/// patient selects one service.
List<Dentist> doctorsForService(DentalService service) =>
    kDentists.where((dentist) => dentist.canPerform(service)).toList();

/// Whether anyone credentialed for [services] holds clinic on [day].
///
/// This is what keeps the booking chain honest: a day nobody credentialed is
/// in must not be offered, or the summary names no dentist for a visit the
/// patient has already paid a downpayment on.
bool hasEligibleDentistOn(Iterable<DentalService> services, DateTime day) =>
    assignedDentistFor(services, day) != null;

/// The weekdays at least one dentist credentialed for [services] holds clinic,
/// sorted Monday-first. Empty when nobody on the roster covers the selection.
List<int> eligibleClinicDays(Iterable<DentalService> services) {
  final days = <int>{};
  for (final dentist in eligibleDentists(services)) {
    days.addAll(dentist.clinicDays.where(clinicOperatingDays.contains));
  }
  final sorted = days.toList()..sort();
  return sorted;
}

/// What to print under a doctor's name so the patient is never left guessing
/// what the person treating them is credentialed for.
///
/// Prefers the dentist's own title. Falls back to the credentials the booked
/// procedures demand — that is still true of whoever the clinic staffs — and
/// only then to a plain "the clinic confirms it" line. It never returns empty:
/// a booking must always announce a specialization.
String doctorSpecializationLabel(String? doctorName, {Iterable<String> serviceIds = const []}) {
  final name = doctorName?.trim() ?? '';
  final rostered = name.isEmpty ? null : dentistByName(name);
  if (rostered != null) return rostered.title;

  final required = <String>{};
  for (final id in serviceIds) {
    final service = serviceById(id);
    if (service != null) required.add(service.requiredSpecialization);
  }
  if (required.isNotEmpty) return '${required.join(' · ')} required';

  return kSpecializationPending;
}

/// The rostered dentist called [name], or null.
///
/// Matched on the bare name: the clinic stores "Rey Vincent Bolasoc" while the
/// app writes "Dr. Rey Vincent Bolasoc" onto bookings, and an exact compare made
/// every such doctor look unrostered — which showed the credential the visit
/// needs instead of the title the dentist actually holds.
Dentist? dentistByName(String name) {
  final wanted = _bareName(name);
  if (wanted.isEmpty) return null;
  for (final dentist in kDentists) {
    if (_bareName(dentist.name) == wanted) return dentist;
  }
  return null;
}

/// The clinic's rostered dentist with database id [id], or null.
///
/// Only the clinic's own roster: the built-in fallback ids never match a row.
/// This is how a record whose embedded `members` row came back empty — a
/// patient session cannot read `members` directly — still names its dentist.
Dentist? dentistById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final dentist in ClinicCatalog().doctors) {
    if (dentist.id == id) return dentist;
  }
  return null;
}

/// Lowercase, no honorific, single-spaced.
String _bareName(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'^\s*(dr|doc|doctor)\.?\s+'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

// --- Operating schedule ---

/// Built-in week, used only until `clinic_settings` / `clinic_closures` have
/// loaded (and in tests). The clinic's own rows win once [ClinicCatalog] has
/// them — see [clinicOperatingDays].
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

/// Weekdays the clinic opens, from `clinic_closures` (recurring all-day rows
/// close a weekday). Falls back to [kClinicOperatingDays] before the load.
Set<int> get clinicOperatingDays =>
    ClinicCatalog().schedule?.operatingDays ?? kClinicOperatingDays;

/// Opening and closing time from `clinic_settings`, in minutes from midnight.
int get clinicOpenMinute => ClinicCatalog().schedule?.openMinute ?? kClinicOpenMinute;
int get clinicCloseMinute => ClinicCatalog().schedule?.closeMinute ?? kClinicCloseMinute;

/// Open on [day]: an operating weekday that is not a dated all-day closure
/// (a holiday the clinic entered in `clinic_closures`).
bool isClinicOpenOn(DateTime day) {
  if (!clinicOperatingDays.contains(day.weekday)) return false;
  return !(ClinicCatalog().schedule?.isClosedAllDay(day) ?? false);
}

/// Whether a partial closure on [day] overlaps `[startMinute, endMinute)`.
bool isClinicClosedDuring(DateTime day, int startMinute, int endMinute) =>
    ClinicCatalog().schedule?.overlapsClosure(day, startMinute, endMinute) ?? false;

const List<String> _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String weekdayLabel(int weekday) => _weekdayNames[weekday - 1];

/// "Wed – Sun" style summary of the operating week.
String get clinicOperatingDaysLabel {
  final days = clinicOperatingDays.toList()..sort();
  if (days.isEmpty) return 'Closed';
  if (days.length == 1) return weekdayLabel(days.first);
  return '${weekdayLabel(days.first)} – ${weekdayLabel(days.last)}';
}

String get clinicHoursLabel =>
    '${formatMinuteOfDay(clinicOpenMinute)} – ${formatMinuteOfDay(clinicCloseMinute)}';

/// Every 15-minute start on [day] that leaves room for a [durationMinutes]
/// block before closing and does not run into a partial closure. Empty on a
/// day the clinic is closed.
List<int> slotStartsFor(DateTime day, int durationMinutes) {
  if (!isClinicOpenOn(day) || durationMinutes <= 0) return const [];
  final starts = <int>[];
  for (var minute = clinicOpenMinute;
      minute + durationMinutes <= clinicCloseMinute;
      minute += kSlotStepMinutes) {
    if (isClinicClosedDuring(day, minute, minute + durationMinutes)) continue;
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
