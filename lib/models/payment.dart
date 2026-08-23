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

  Payment({
    required this.id,
    required this.referenceNo,
    required this.procedureName,
    required this.doctorName,
    required this.amount,
    required this.billedOn,
    required this.status,
    this.paymentMethod,
  });
}