import 'package:flutter/cupertino.dart';

enum TransactionType { credit, debit }

/// What a ledger row did to the balance, read the way the website's
/// `_walletKind` (js/patient-wallet.js) reads it. Refund and adjustment rows
/// are recognised by their description, so one arriving later is not shown
/// as a cash-in.
enum WalletTxnKind { credit, refund, adjust, debit }

/// One `wallet_transactions` row: money that actually moved the wallet
/// balance. A GCash or GrabPay payment made straight to a booking or a bill
/// writes no row here and so is not in this list.
class WalletTransaction {
  final String id;
  final String title;
  final String subtitle;
  final double amount;
  final TransactionType type;
  final IconData icon;

  /// `created_at`, as an instant.
  final DateTime dateTime;

  /// The stored `reference_no` (PayMongo's payment id for a cash-in). The
  /// 13-digit number the patient sees is derived from it and never replaces it.
  final String referenceNo;

  /// The stored `method` (`GCash`, `grab_pay`, `Wallet`, …).
  final String method;

  /// The stored `description`, or empty.
  final String description;

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
    this.description = '',
  });

  bool get isCredit => type == TransactionType.credit;

  WalletTxnKind get kind {
    if (RegExp('adjust|correction', caseSensitive: false).hasMatch(description)) {
      return WalletTxnKind.adjust;
    }
    if (isCredit && RegExp('refund', caseSensitive: false).hasMatch(description)) {
      return WalletTxnKind.refund;
    }
    return isCredit ? WalletTxnKind.credit : WalletTxnKind.debit;
  }
}
