import 'dental_service.dart';

/// A clinic dentist. [specializations] are matched against each selected
/// service's `requiredSpecialization` to decide who may perform the visit.
class Dentist {
  final String id;
  final String name;
  final String title;
  final Set<String> specializations;

  /// Days of the week this dentist holds clinic, as `DateTime.weekday` values.
  final Set<int> clinicDays;

  const Dentist({
    required this.id,
    required this.name,
    required this.title,
    required this.specializations,
    required this.clinicDays,
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

  bool canPerform(DentalService service) =>
      specializations.contains(service.requiredSpecialization);

  /// True only when this dentist covers *every* selected procedure — a visit
  /// is booked with one dentist, so partial coverage is not bookable.
  bool canPerformAll(Iterable<DentalService> services) => services.every(canPerform);

  String get initials {
    final parts = name.replaceFirst(RegExp(r'^Dr\.?\s*'), '').split(' ')
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
