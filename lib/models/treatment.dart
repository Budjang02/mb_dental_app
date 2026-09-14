/// Represents a completed treatment or clinical note entry.
class Treatment {
  final String id;
  final String procedure;
  final String doctorName;
  final DateTime date;
  final String notes;

  Treatment({
    required this.id,
    required this.procedure,
    required this.doctorName,
    required this.date,
    required this.notes,
  });
}

/// One procedure the clinic has *planned* rather than performed — the entries
/// listed under Records → Treatment Plan. [plannedFor] is null while a
/// procedure is proposed but not yet scheduled.
class TreatmentPlanItem {
  final String id;
  final String procedure;
  final String toothLabel;
  final String doctorName;
  final DateTime? plannedFor;
  final double estimatedCost;
  final String notes;

  TreatmentPlanItem({
    required this.id,
    required this.procedure,
    required this.toothLabel,
    required this.doctorName,
    this.plannedFor,
    required this.estimatedCost,
    this.notes = '',
  });
}

/// One `treatment_plans` row as the notification feed needs it.
class TreatmentPlanSummary {
  final String id;
  final String title;

  /// `treatment_plans.status` as stored (`active`, `completed`, `cancelled`).
  final String status;

  /// `updated_at ?? created_at`, exactly as the database returned it. The
  /// plan notice is keyed on this string, so an edit to the plan produces a
  /// new key and a new unread notice.
  final String stamp;

  /// True when the plan has an `updated_at` that differs from its creation.
  final bool wasUpdated;

  /// `updated_at`, or null when the row has none. The website lists plans by
  /// this column, newest first.
  final DateTime? updatedAt;

  /// [stamp] as a time, for ordering the feed.
  final DateTime changedAt;

  const TreatmentPlanSummary({
    required this.id,
    required this.title,
    required this.stamp,
    required this.wasUpdated,
    required this.changedAt,
    this.status = '',
    this.updatedAt,
  });
}
