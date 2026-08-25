import 'package:flutter/cupertino.dart';

enum TransactionType { credit, debit }

/// Represents a single wallet ledger entry (top-up, payment, down payment, etc).
class WalletTransaction {
  final String id;
  final String title;
  final String subtitle;
  final double amount;
  final TransactionType type;
  final IconData icon;
  final DateTime dateTime;
  final String referenceNo;
  final String method;

  WalletTransaction({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.type,
    required this.icon,
    required this.dateTime,
    required this.referenceNo,
    required this.method,
  });

  bool get isCredit => type == TransactionType.credit;
}
