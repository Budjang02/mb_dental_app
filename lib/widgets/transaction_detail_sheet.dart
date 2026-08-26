import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatTxnDate(DateTime date) => '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';

String formatTxnTime(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

void showTransactionDetailSheet(BuildContext context, WalletTransaction txn) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(dialogContext).size.height * 0.82),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () => Navigator.pop(dialogContext),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(CupertinoIcons.xmark_circle_fill, size: 22, color: AppColors.textSecondary),
                  ),
                ),
              ),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
                  child: Icon(txn.icon, color: AppColors.primary, size: 28),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '${txn.isCredit ? '+' : '-'} ₱${txn.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: txn.isCredit ? AppColors.success : AppColors.error,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(child: Text(txn.title, style: TextStyle(fontSize: 14, color: AppColors.textSecondary))),
              const SizedBox(height: 20),
              const Divider(),
              _kv('Reference No.', txn.referenceNo),
              _kv('Date', formatTxnDate(txn.dateTime)),
              _kv('Time', formatTxnTime(txn.dateTime)),
              _kv('Method', txn.method),
              _kv('Status', 'Completed'),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _kv(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ],
    ),
  );
}
