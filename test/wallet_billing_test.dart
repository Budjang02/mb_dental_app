import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/models/payment.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/screens/wallet/billing_receipts.dart';
import 'package:mb_dental_app/widgets/wallet_txn_widgets.dart';

WalletTransaction _txn({
  bool credit = true,
  String method = 'GCash',
  String description = '',
  DateTime? at,
}) =>
    WalletTransaction(
      id: 't',
      title: '',
      subtitle: '',
      amount: 1000,
      type: credit ? TransactionType.credit : TransactionType.debit,
      icon: CupertinoIcons.creditcard,
      dateTime: at ?? DateTime.utc(2026, 9, 30, 2, 30),
      referenceNo: 'pay_4f9XyZ12abcD',
      method: method,
      description: description,
    );

Payment _charge(
  String id, {
  double amount = 1000,
  String status = 'Unpaid',
  String? receiptId,
  bool voided = false,
}) =>
    Payment(
      id: id,
      referenceNo: id,
      procedureName: 'Cleaning',
      doctorName: '',
      amount: amount,
      billedOn: DateTime.utc(2026, 9, 1),
      status: status,
      invoiceNo: '',
      receiptId: receiptId,
      voidedAt: voided ? DateTime.utc(2026, 9, 2) : null,
    );

void main() {
  group('ledger rows read like the website', () {
    test('cash in', () {
      final t = _txn(method: 'gcash');
      expect(t.kind, WalletTxnKind.credit);
      expect(txnTitle(t), 'Cash in from GCash');
      expect(txnMethodLabel(t), 'Cash In from GCash');
      expect(txnNote(t), 'Added to your wallet balance from GCash.');
      expect(txnAmountLabel(t), '+ ₱1,000.00');
      expect(txnTitle(_txn(method: 'grab_pay')), 'Cash in from GrabPay');
      expect(txnTitle(_txn(method: '')), 'Cash In');
    });

    test('payments out', () {
      final pay = _txn(credit: false, method: 'Wallet', description: 'Paid Cleaning');
      expect(txnTitle(pay), 'Wallet Payment');
      expect(txnMethodLabel(pay), 'Wallet Balance');
      expect(txnNote(pay), 'Deducted from your wallet balance.');
      expect(txnAmountLabel(pay), '− ₱1,000.00');
      expect(txnTitle(_txn(credit: false, description: 'Appointment downpayment')), 'Appointment Downpayment');
    });

    test('refunds and adjustments only from what the row says', () {
      final refund = _txn(method: 'Wallet', description: 'Refund for cancelled visit');
      expect(txnTitle(refund), 'Refund');
      expect(txnMethodLabel(refund), 'Wallet Balance');
      expect(txnNote(refund), 'Returned to your wallet balance.');
      final adjust = _txn(credit: false, method: '', description: 'Balance correction');
      expect(txnTitle(adjust), 'Wallet Adjustment');
      expect(txnNote(adjust), 'Adjusted by the clinic.');
    });

    test('details time is Manila', () {
      expect(formatTxnDateTime(_txn().dateTime), 'Sep 30, 2026, 10:30 AM');
    });

    test('date ranges', () {
      final now = DateTime.utc(2026, 9, 30, 4); // 12:00 in Manila
      final lastNight = _txn(at: DateTime.utc(2026, 9, 29, 15, 30)); // 23:30 Manila, the 29th
      final thisMorning = _txn(at: DateTime.utc(2026, 9, 29, 16, 30)); // 00:30 Manila, the 30th
      expect(walletInRange(lastNight, WalletRange.today, now: now), isFalse);
      expect(walletInRange(thisMorning, WalletRange.today, now: now), isTrue);
      expect(walletInRange(_txn(at: DateTime.utc(2026, 9, 1)), WalletRange.last30, now: now), isTrue);
      expect(walletInRange(_txn(at: DateTime.utc(2026, 8, 30)), WalletRange.last30, now: now), isFalse);
      expect(walletEmptyMessage(WalletRange.last7, WalletDirection.all), 'No transactions in this period.');
      expect(walletEmptyMessage(WalletRange.all, WalletDirection.moneyOut), 'Nothing paid from the wallet yet.');
    });
  });

  group('Billing & Receipts', () {
    test('voided charges count nowhere; one receipt covering two charges counts once', () {
      final summary = BillingSummary.of([
        _charge('a', status: 'Paid', receiptId: 'r1'),
        _charge('b', amount: 500, status: 'Paid', receiptId: 'r1'),
        _charge('c', amount: 250),
        _charge('d', amount: 9999, voided: true),
      ]);
      expect(summary.paid, 1500);
      expect(summary.outstanding, 250);
      expect(summary.receipts, 1);
    });

    test('status', () {
      expect(_charge('a', status: 'Paid').statusLabel, 'Paid');
      expect(_charge('b').statusLabel, 'Unpaid');
      expect(_charge('c', status: 'Paid', voided: true).statusLabel, 'Voided');
      expect(_charge('c', voided: true).isOwed, isFalse);
      expect(billingStatusStyle(_charge('a', status: 'Paid')).$2, const Color(0xFF16A34A));
      expect(billingStatusStyle(_charge('b')).$2, const Color(0xFFD97706));
      expect(billingStatusStyle(_charge('c', voided: true)).$2, const Color(0xFF64748B));
    });
  });
}
