/// Tooth conditions strictly matching the clinical Odontogram chart.
enum ToothCondition { healthy, cavity, filled, crown, missing, rootCanal, impacted }

/// Represents an individual tooth condition for the adult dental chart (1-32).
class ToothRecord {
  final String toothId;
  final ToothCondition condition;
  final String? notes;

  ToothRecord({
    required this.toothId,
    required this.condition,
    this.notes,
  });
}