import 'package:flutter/cupertino.dart';

/// The four service groups the booking wizard lists procedures under.
enum ServiceCategory { preventive, restorative, orthodontics, esthetic }

extension ServiceCategoryX on ServiceCategory {
  String get label {
    switch (this) {
      case ServiceCategory.preventive:
        return 'Preventive';
      case ServiceCategory.restorative:
        return 'Restorative';
      case ServiceCategory.orthodontics:
        return 'Orthodontics';
      case ServiceCategory.esthetic:
        return 'Esthetic';
    }
  }

  String get blurb {
    switch (this) {
      case ServiceCategory.preventive:
        return 'Routine care that keeps problems from starting.';
      case ServiceCategory.restorative:
        return 'Repair and rebuild damaged or missing teeth.';
      case ServiceCategory.orthodontics:
        return 'Straighten teeth and correct the bite.';
      case ServiceCategory.esthetic:
        return 'Improve the look of your smile.';
    }
  }

  IconData get icon {
    switch (this) {
      case ServiceCategory.preventive:
        return CupertinoIcons.shield_lefthalf_fill;
      case ServiceCategory.restorative:
        return CupertinoIcons.wrench;
      case ServiceCategory.orthodontics:
        return CupertinoIcons.wand_rays;
      case ServiceCategory.esthetic:
        return CupertinoIcons.sparkles;
    }
  }
}

/// A bookable procedure. [durationMinutes] is what the wizard sums to size the
/// appointment block, and [requiredSpecialization] is what Step 2 matches
/// against each dentist's credentials.
class DentalService {
  final String id;
  final String name;
  final String description;
  final ServiceCategory category;

  /// Chair time in minutes. Always a multiple of the 15-minute booking grid.
  final int durationMinutes;

  final double price;

  /// The credential a dentist must hold to perform this procedure — e.g. an
  /// Orthodontist for braces.
  final String requiredSpecialization;

  final IconData icon;

  const DentalService({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.durationMinutes,
    required this.price,
    required this.requiredSpecialization,
    required this.icon,
  });

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
