import '../app/messages.dart';

/// One heading the booking wizard groups procedures under.
///
/// These are the clinic's own specializations, loaded from the `specializations`
/// table rather than fixed in the app — the clinic adds or retires a service
/// line without a new build.
class ServiceGroup {
  /// The code procedures point at (`general`, `ortho`, `surgery`, …).
  final String code;

  final String label;
  final String blurb;

  /// Where the clinic wants this group to sit in the list.
  final int sortOrder;

  const ServiceGroup({
    required this.code,
    required this.label,
    required this.blurb,
    required this.sortOrder,
  });

  @override
  bool operator ==(Object other) => other is ServiceGroup && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// A bookable procedure. [durationMinutes] is what the wizard sums to size the
/// appointment block, and [requiredSpecialization] is what Step 2 matches
/// against each dentist's credentials.
class DentalService {
  final String id;
  final String name;
  final String description;

  /// The clinic's own specialization code (`ortho`, `surgery`, …). Not what
  /// the wizard groups by — it is what the dentist roster matches credentials
  /// against, via [requiredSpecialization].
  final String specializationCode;

  /// The patient-facing group this is listed under. See
  /// `data/service_categories.dart`.
  final String categoryId;

  /// Chair time in minutes. Always a multiple of the 15-minute booking grid.
  final int durationMinutes;

  final double price;

  /// The credential a dentist must hold to perform this procedure — e.g. an
  /// Orthodontist for braces.
  final String requiredSpecialization;

  /// How the clinic prices it: `Per tooth`, `Per arch`, `Flat`, and so on.
  /// Blank when the clinic has not said, and shown next to the amount so a
  /// per-tooth price is never read as the whole bill.
  final String priceUnit;

  const DentalService({
    required this.id,
    required this.name,
    required this.description,
    required this.specializationCode,
    required this.categoryId,
    required this.durationMinutes,
    required this.price,
    required this.requiredSpecialization,
    this.priceUnit = '',
  });

  /// What to print where the price goes.
  ///
  /// Much of the clinic's menu is quoted at the chair rather than priced up
  /// front, and a lot of the rest is priced per tooth or per arch. Printing a
  /// bare peso figure for either would read as the price of the whole visit,
  /// so the unit travels with the amount and an unpriced procedure says so.
  String get priceLabel {
    if (price <= 0) return 'Quoted at clinic';
    final amount = formatPeso(price);
    if (priceUnit.isEmpty || priceUnit.toLowerCase() == 'flat') return amount;
    return '$amount · ${priceUnit.toLowerCase()}';
  }

  /// "1 hr 30 min" / "45 min" — used wherever a duration is shown to patients.
  String get durationLabel => formatDuration(durationMinutes);

  @override
  bool operator ==(Object other) => other is DentalService && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

String formatDuration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  final hourLabel = '$hours hr';
  return rest == 0 ? hourLabel : '$hourLabel $rest min';
}
