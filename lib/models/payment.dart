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
  });

  bool get isPaid => status.toLowerCase() == 'paid';
}