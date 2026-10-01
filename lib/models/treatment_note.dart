/// Who a treatment note is attributed to, resolved the way the website's
/// `_trnAttribution()` (js/odontogram.js) resolves it.
class NoteAttribution {
  /// "Dr. Rey Vincent Bolasoc", "Dr. Reyes (via Staff)",
  /// "Clinic Staff (Ana Cruz)" or the clinic team fallback.
  final String primary;

  /// "Attending Dentist", "Staff / Attending Dentist", "Clinic Staff", … or
  /// empty.
  final String secondary;

  /// Entered by staff or an admin rather than by the dentist.
  final bool staffEntered;

  /// True when no dentist is named — the label is then "Recorded by", so a
  /// staff member is never presented as the doctor.
  final bool staffOnly;

  const NoteAttribution({
    required this.primary,
    this.secondary = '',
    this.staffEntered = false,
    this.staffOnly = false,
  });

  static const String clinicTeam = 'Mariano & Bolasoc Dental Team';
  static const String clinic = 'Mariano & Bolasoc Dental Center';

  /// "Dr. " once, and only for a dentist.
  static String dentistName(String name) {
    final value = name.trim();
    if (value.isEmpty) return '';
    return RegExp(r'^dr\.?\s', caseSensitive: false).hasMatch(value) ? value : 'Dr. $value';
  }

  static NoteAttribution resolve({
    required String attendingName,
    required String legacyDoctorName,
    required String recorderName,
    required String recordedByRole,
  }) {
    final role = recordedByRole.trim().toLowerCase();
    final attending = attendingName.trim().isNotEmpty ? attendingName.trim() : legacyDoctorName.trim();
    final recorder = recorderName.trim();
    final byStaff = role == 'admin' || role == 'staff';

    if (attending.isNotEmpty) {
      return NoteAttribution(
        primary: dentistName(attending) + (byStaff ? ' (via Staff)' : ''),
        secondary: byStaff ? 'Staff / Attending Dentist' : 'Attending Dentist',
        staffEntered: byStaff,
      );
    }
    if (role == 'admin') {
      return NoteAttribution(
        primary: recorder.isNotEmpty ? 'Clinic Admin ($recorder)' : clinicTeam,
        secondary: recorder.isNotEmpty ? 'Clinic Administration' : '',
        staffEntered: true,
        staffOnly: true,
      );
    }
    if (role == 'staff') {
      return NoteAttribution(
        primary: recorder.isNotEmpty ? 'Clinic Staff ($recorder)' : clinicTeam,
        secondary: recorder.isNotEmpty ? 'Clinic Staff' : '',
        staffEntered: true,
        staffOnly: true,
      );
    }
    if (role == 'dentist' && recorder.isNotEmpty) {
      return NoteAttribution(primary: dentistName(recorder), secondary: 'Attending Dentist');
    }
    return const NoteAttribution(primary: clinic);
  }
}

/// One active `treatment_notes` row, as the patient reads it.
class TreatmentNote {
  final String id;
  final DateTime? createdAt;

  /// `tooth_id` exactly as stored ("1", "#1", "A", "p_a", or free text).
  final String toothId;

  /// The condition wording as stored, or empty.
  final String condition;

  /// The clinical text, verbatim (`notes`; a newer client may call it
  /// `clinical_notes`).
  final String notes;
  final String? appointmentId;
  final NoteAttribution attribution;

  const TreatmentNote({
    required this.id,
    required this.createdAt,
    required this.toothId,
    required this.condition,
    required this.notes,
    required this.attribution,
    this.appointmentId,
  });

  /// The chart key for [toothId] — the website's `_trnToothKey`: "1" / "#1"
  /// is the permanent tooth "1" (1–32); "A" / "p_a" is the primary tooth
  /// "P_A" (A–T). Empty when it names no tooth.
  static String toothKeyOf(String id) {
    final s = id.trim().replaceFirst(RegExp('^#'), '').toUpperCase();
    if (RegExp(r'^([1-9]|[12]\d|3[0-2])$').hasMatch(s)) return s;
    final m = RegExp(r'^(?:P_)?([A-T])$').firstMatch(s);
    return m == null ? '' : 'P_${m.group(1)}';
  }

  String get toothKey => toothKeyOf(toothId);

  /// "#1", "A (primary)", the stored text for anything else, or
  /// "Not recorded".
  String get toothLabel {
    final key = toothKey;
    if (key.isEmpty) return toothId.trim().isEmpty ? 'Not recorded' : toothId.trim();
    return key.startsWith('P_') ? '${key.substring(2)} (primary)' : '#$key';
  }

  /// The permanent tooth number the app's chart draws, or null (primary teeth
  /// and unlinked notes have none on it).
  int? get permanentTooth {
    final key = toothKey;
    return key.isEmpty || key.startsWith('P_') ? null : int.parse(key);
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static DateTime _manila(DateTime d) => d.toUtc().add(const Duration(hours: 8));

  /// "Sep 16, 2026" in Asia/Manila, or "—".
  String get dateLabel {
    final at = createdAt;
    if (at == null) return '—';
    final m = _manila(at);
    return '${_months[m.month - 1]} ${m.day}, ${m.year}';
  }

  /// "10:05 AM" in Asia/Manila, or empty.
  String get timeLabel {
    final at = createdAt;
    if (at == null) return '';
    final m = _manila(at);
    final h = m.hour % 12 == 0 ? 12 : m.hour % 12;
    return '$h:${m.minute.toString().padLeft(2, '0')} ${m.hour >= 12 ? 'PM' : 'AM'}';
  }
}
