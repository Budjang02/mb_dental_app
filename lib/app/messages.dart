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
