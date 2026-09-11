/// One line of the conversation between a patient and the clinic front desk.
class PatientMessage {
  final String id;
  final String body;

  /// Whose side of the thread this sits on. Drawn from `sender_role`, so a
  /// message the clinic sent from any of its accounts still reads as the
  /// clinic rather than as a second patient.
  final bool fromPatient;

  final DateTime sentAt;

  /// Null until the other side has opened it.
  final DateTime? readAt;

  const PatientMessage({
    required this.id,
    required this.body,
    required this.fromPatient,
    required this.sentAt,
    this.readAt,
  });

  bool get isRead => readAt != null;

  @override
  bool operator ==(Object other) => other is PatientMessage && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
