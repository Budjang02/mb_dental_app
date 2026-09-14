/// Represents patient billing statements and digital receipts.
class Payment {
  final String id;
  final String referenceNo;
  final String procedureName;
  final String doctorName;
  final double amount;
  final DateTime billedOn;
  final String status; // 'Paid' or 'Unpaid'
  final String? paymentMethod;

  /// Statement number — every billed procedure has one.
  final String invoiceNo;

  /// Only issued once the statement is settled, so null while unpaid.
  final String? receiptNo;

  /// `payment_receipts.id` behind [receiptNo]. The "payment received" notice
  /// is keyed on it, the same way the website keys it.
  final String? receiptId;

  /// When the clinic issued that receipt.
  final DateTime? receiptIssuedAt;

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
    this.receiptNo,
    this.receiptId,
    this.receiptIssuedAt,
  });

  bool get isPaid => status.toLowerCase() == 'paid';
}
