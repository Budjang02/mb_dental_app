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