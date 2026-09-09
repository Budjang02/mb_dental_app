import 'package:flutter/cupertino.dart';

/// What a patient-supplied file actually is. The kind drives the glyph and
/// the label shown next to it in the picker, so a referral never reads as an
/// X-ray in the list.
enum DocumentKind { prescription, referral, xray, insurance, other }

extension DocumentKindX on DocumentKind {
  String get label {
    switch (this) {
      case DocumentKind.prescription:
        return 'Prescription';
      case DocumentKind.referral:
        return 'Dental request';
      case DocumentKind.xray:
        return 'X-ray';
      case DocumentKind.insurance:
        return 'Insurance';
      case DocumentKind.other:
        return 'Document';
    }
  }

  IconData get icon {
    switch (this) {
      case DocumentKind.prescription:
        return CupertinoIcons.doc_text;
      case DocumentKind.referral:
        return CupertinoIcons.doc_plaintext;
      case DocumentKind.xray:
        return CupertinoIcons.doc_richtext;
      case DocumentKind.insurance:
        return CupertinoIcons.shield_lefthalf_fill;
      case DocumentKind.other:
        return CupertinoIcons.paperclip;
    }
  }
}

/// A file the patient has uploaded to their record — a dentist's prescription,
/// a referral slip, an outside X-ray. Booking attaches one of these to a visit
/// so the clinic knows what was requested before the patient arrives.
class PatientDocument {
  final String id;
  final String name;
  final DocumentKind kind;
  final DateTime uploadedOn;

  /// Where the file lives. Null for the seeded demo entries, which stand in
  /// for records uploaded from another device.
  final String? path;

  const PatientDocument({
    required this.id,
    required this.name,
    required this.kind,
    required this.uploadedOn,
    this.path,
  });

  @override
  bool operator ==(Object other) => other is PatientDocument && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
