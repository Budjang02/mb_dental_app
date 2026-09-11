import 'package:flutter/material.dart';

/// The exact patient-facing strings the system spec fixes wording for. Screens
/// reference these rather than inlining copy, so the wording stays identical
/// everywhere it is shown — toast, push alert and notification centre alike.
class AppMessages {
  const AppMessages._();

  // --- Success ---
  static const String appointmentScheduled = 'Appointment scheduled successfully!';
  static const String paymentProcessed = 'Payment processed and receipt generated.';

  // --- Error ---
  static const String insufficientBalance =
      'Insufficient wallet balance for 20% downpayment.';
  static const String slotUnavailable = 'Selected time slot is no longer available.';
}

/// Share of the visit total charged up front to secure a slot.
const double kDownPaymentRate = 0.20;

/// The 20% downpayment for a [total] visit cost, rounded to centavos.
double downPaymentFor(double total) =>
    (total * kDownPaymentRate * 100).roundToDouble() / 100;

/// Peso amounts, formatted with thousands separators: `₱12,345.00`.
/// Stand-in for a visit the clinic has not staffed yet. Patients do not pick
/// their own doctor, so a booking is routinely unassigned until the clinic
/// confirms it — printing an empty line there reads as missing data.
const String kUnassignedDoctor = 'To be assigned';

/// The glyph that marks a doctor wherever one is named. A medical bag rather
/// than a plain person outline, so the name next to it needs no "Doctor:"
/// prefix to say who it belongs to.
const IconData kDoctorIcon = Icons.medical_services_outlined;

/// Stand-in for a doctor the clinic has assigned but whose staff record this
/// patient's session is not permitted to read. Distinct from
/// [kUnassignedDoctor], which means no doctor has been picked at all.
const String kDoctorAssignedUnnamed = 'Assigned by the clinic';

/// The doctor's name, or [kUnassignedDoctor] when nobody is named yet. Every
/// screen that shows a doctor goes through this so they cannot disagree about
/// what an empty name looks like.
String doctorLabel(String? name) {
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? kUnassignedDoctor : trimmed;
}

String formatPeso(double amount) {
  final fixed = amount.toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return '₱$buffer.${parts[1]}';
}
