import 'dental_service.dart';

/// One working window from `doctor_schedules`: the dentist is in from
/// [startMinute] to [endMinute] (minutes from midnight), except during the
/// break when both break times are set.
class DoctorHours {
  final int startMinute;
  final int endMinute;
  final int? breakStartMinute;
  final int? breakEndMinute;

  const DoctorHours({
    required this.startMinute,
    required this.endMinute,
    this.breakStartMinute,
    this.breakEndMinute,
  });

  /// Whether a visit from [start] to [end] fits inside this window without
  /// running into the break. Half-open: a visit may end exactly as the break
  /// starts, or start exactly as it ends.
  bool covers(int start, int end) {
    if (start < startMinute || end > endMinute) return false;
    final breakStart = breakStartMinute;
    final breakEnd = breakEndMinute;
    if (breakStart != null && breakEnd != null && start < breakEnd && breakStart < end) {
      return false;
    }
    return true;
  }
}

/// A clinic dentist. [specializations] are matched against each selected
/// service's `requiredSpecialization` to decide who may perform the visit.
class Dentist {
  final String id;
  final String name;
  final String title;
  final Set<String> specializations;

  /// The clinic's own specialization codes this dentist holds (`general`,
  /// `ortho`, `surgery`, …), from `members.specialization(s)`.
  ///
  /// Matching runs on these when they are known, because it is the same column
  /// `procedures.specialization` carries — no label translation in between.
  /// Empty for the built-in fallback roster, which matches on
  /// [specializations] instead.
  final Set<String> specializationCodes;

  /// Procedure ids the clinic has explicitly assigned this dentist in
  /// `member_services`. When the clinic has filled that table in for a dentist
  /// it is the authoritative answer to "who can perform this", ahead of codes.
  final Set<String> procedureIds;

  /// Days of the week this dentist holds clinic, as `DateTime.weekday` values.
  final Set<int> clinicDays;

  /// Upcoming whole days off from `doctor_schedule_exceptions`, date-only.
  final Set<DateTime> offDates;

  /// Working windows per `DateTime.weekday`, from `doctor_schedules`. Empty
  /// when the hours could not be read, in which case the dentist is taken to
  /// work the clinic's opening hours on their clinic days.
  final Map<int, List<DoctorHours>> hoursByWeekday;

  /// Profile photo from `profiles.avatar_url`, or null.
  final String? avatarUrl;

  const Dentist({
    required this.id,
    required this.name,
    required this.title,
    required this.specializations,
    required this.clinicDays,
    this.specializationCodes = const {},
    this.procedureIds = const {},
    this.offDates = const {},
    this.hoursByWeekday = const {},
    this.avatarUrl,
  });

  /// Sentinel for the "let the clinic assign someone" choice in Step 2. It is
  /// never filtered out, and booking with it leaves the dentist unassigned.
  static const Dentist anyAvailable = Dentist(
    id: 'any',
    name: 'Any Available Doctor',
    title: 'The clinic assigns the best-matched dentist',
    specializations: {},
    clinicDays: {},
  );

  bool get isAnyAvailable => id == anyAvailable.id;

  /// This dentist with [hours] as their working windows.
  Dentist withHours(Map<int, List<DoctorHours>> hours) => Dentist(
        id: id,
        name: name,
        title: title,
        specializations: specializations,
        clinicDays: clinicDays,
        specializationCodes: specializationCodes,
        procedureIds: procedureIds,
        offDates: offDates,
        hoursByWeekday: hours,
        avatarUrl: avatarUrl,
      );

  /// Whether this dentist may perform [service].
  ///
  /// Prefers the clinic's explicit procedure assignments, then its codes, and
  /// falls back to the credential label so the built-in roster still works
  /// when the clinic's roster is unreadable.
  bool canPerform(DentalService service) {
    if (procedureIds.isNotEmpty) return procedureIds.contains(service.id);
    if (specializationCodes.isNotEmpty) {
      return specializationCodes.contains(service.specializationCode);
    }
    return specializations.contains(service.requiredSpecialization);
  }

  /// True only when this dentist covers *every* selected procedure — a visit
  /// is booked with one dentist, so partial coverage is not bookable.
  bool canPerformAll(Iterable<DentalService> services) => services.every(canPerform);

  /// Whether the dentist is in on [day]: a clinic weekday that is not one of
  /// their exception days.
  bool isInOn(DateTime day) =>
      clinicDays.contains(day.weekday) &&
      !offDates.contains(DateTime(day.year, day.month, day.day));

  /// Whether the dentist is working for the whole of a visit from
  /// [startMinute] to [endMinute] on [day]: in that day, and inside one of
  /// that weekday's windows clear of its break. With no hours on record for
  /// the weekday, being in that day is enough.
  bool isAvailableAt(DateTime day, int startMinute, int endMinute) {
    if (!isInOn(day)) return false;
    final windows = hoursByWeekday[day.weekday];
    if (windows == null || windows.isEmpty) return true;
    return windows.any((window) => window.covers(startMinute, endMinute));
  }

  String get initials {
    final parts = name.replaceFirst(RegExp(r'^Dr\.?\s*'), '').split(' ')
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
