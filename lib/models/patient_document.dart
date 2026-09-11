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

/// A file on the patient's record — an X-ray or chart note the clinic added,
/// or a prescription or referral slip the patient uploaded themselves. Booking
/// attaches one of these to a visit so the clinic knows what was requested
/// before the patient arrives.
class PatientDocument {
  final String id;
  final String name;
  final DocumentKind kind;
  final DateTime uploadedOn;

  /// Object path inside the storage bucket. Null when the clinic recorded the
  /// file against the chart without attaching one.
  final String? path;

  /// The doctor or staff member who put the file on the record. Empty for a
  /// file the patient uploaded themselves, and for older rows saved before the
  /// clinic started recording an uploader.
  final String uploadedBy;

  /// Whatever the clinic recorded in `file_type` — sometimes an extension
  /// (`jpg`), sometimes a media type (`image/jpeg`). Both shapes are handled
  /// by [isImage] and [isPdf] rather than assuming one.
  final String fileType;

  /// Size in bytes, or null when the clinic did not record one.
  final int? fileSizeBytes;

  const PatientDocument({
    required this.id,
    required this.name,
    required this.kind,
    required this.uploadedOn,
    this.path,
    this.uploadedBy = '',
    this.fileType = '',
    this.fileSizeBytes,
  });

  String get _typeHint => '$fileType ${name.split('.').last}'.toLowerCase();

  /// Whether the app can render this itself rather than handing it to another
  /// app. Only these two are shown in-app; anything else opens externally.
  bool get isImage =>
      const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif']
          .any(_typeHint.contains) ||
      _typeHint.contains('image/');

  bool get isPdf => _typeHint.contains('pdf');

  bool get isPreviewable => isImage || isPdf;

  /// "1.4 MB" / "820 KB", or empty when the size is unknown.
  String get sizeLabel {
    final bytes = fileSizeBytes;
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  bool operator ==(Object other) => other is PatientDocument && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
