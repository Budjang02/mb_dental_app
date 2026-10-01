/// One `billing_records` charge, as the website's Billing & Receipts lists it.
class Payment {
  final String id;
  final String referenceNo;
  final String procedureName;
  final String doctorName;
  final double amount;
  final DateTime billedOn;

  /// 'Paid' or 'Unpaid', as stored. A voided charge keeps its status; see
  /// [isVoided].
  final String status;

  /// The recorded payment method, including one the clinic recorded at the
  /// desk. Null when nothing was recorded.
  final String? paymentMethod;

  /// The official invoice number, or empty when none has been issued.
  final String invoiceNo;

  /// `invoices.id` behind [invoiceNo], for opening the invoice itself.
  final String? invoiceId;

  /// The payment receipt number, once a receipt covers this charge.
  final String? receiptNo;

  /// `payment_receipts.id` behind [receiptNo]. One receipt can cover several
  /// charges, which is why receipts are counted by this id.
  final String? receiptId;

  /// When the clinic issued that receipt.
  final DateTime? receiptIssuedAt;

  /// Set when the clinic voided the charge. It stays in the history but is
  /// neither owed nor paid.
  final DateTime? voidedAt;

  /// The visit it was billed for, or null for a walk-in charge.
  final String? appointmentId;

  Payment({
    required this.id,
    required this.referenceNo,
    required this.procedureName,
    required this.doctorName,
    required this.amount,
    required this.billedOn,
    required this.status,
    required this.invoiceNo,
    this.paymentMethod,
    this.invoiceId,
    this.receiptNo,
    this.receiptId,
    this.receiptIssuedAt,
    this.voidedAt,
    this.appointmentId,
  });

  bool get isVoided => voidedAt != null;

  bool get isPaid => !isVoided && status.toLowerCase() == 'paid';

  /// Unpaid and not voided: what Pay Bill can settle.
  bool get isOwed => !isVoided && status.toLowerCase() != 'paid';

  /// 'Paid', 'Unpaid' or 'Voided'.
  String get statusLabel => isVoided ? 'Voided' : (isPaid ? 'Paid' : 'Unpaid');
}

/// A bill the clinic sent from Complete & Bill with "Patient's account":
/// one `visit_payment_requests` row.
class VisitPaymentRequest {
  final String id;
  final double amount;

  /// `pending`, `paid` or `cancelled`.
  final String status;
  final DateTime createdAt;
  final String? appointmentId;

  /// The visit's `appointment_date`, as stored (`2026-09-28`), or empty.
  final String visitDate;

  /// The itemised bill the clinic sent with it, or null for a request sent
  /// before breakdowns existed.
  final Map<String, dynamic>? breakdown;

  const VisitPaymentRequest({
    required this.id,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.appointmentId,
    this.visitDate = '',
    this.breakdown,
  });

  bool get isPending => status == 'pending';
}
