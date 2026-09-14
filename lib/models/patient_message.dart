/// One line of the conversation between a patient and the clinic front desk.
class PatientMessage {
  final String id;
  final String body;

  /// Whose side of the thread this sits on. Drawn from `sender_role`, so a
  /// message the clinic sent from any of its accounts still reads as the
  /// clinic rather than as a second patient.
  final bool fromPatient;

  /// `patient_messages.sender_role` as stored (`patient` / `clinic`), or empty
  /// when the row has none.
  final String senderRole;

  final DateTime sentAt;

  /// Null until the other side has opened it. The row's own `read_at` is the
  /// read state on both the app and the website.
  final DateTime? readAt;

  const PatientMessage({
    required this.id,
    required this.body,
    required this.fromPatient,
    required this.sentAt,
    this.senderRole = '',
    this.readAt,
  });

  bool get isRead => readAt != null;

  /// A message from the front desk: `sender_role = 'clinic'`. A row with no
  /// role falls back to "not the patient's own".
  bool get isFromClinic => senderRole.isEmpty ? !fromPatient : senderRole == 'clinic';

  PatientMessage markedRead(DateTime at) => PatientMessage(
        id: id,
        body: body,
        fromPatient: fromPatient,
        senderRole: senderRole,
        sentAt: sentAt,
        readAt: readAt ?? at,
      );

  @override
  bool operator ==(Object other) => other is PatientMessage && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
