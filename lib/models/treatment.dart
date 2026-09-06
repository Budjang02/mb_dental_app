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
