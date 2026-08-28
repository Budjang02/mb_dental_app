import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';

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

/// [onTapNavigate], when given, makes the whole dialog body tappable — used
/// by the Dashboard's Recent Activity so tapping the floating window takes
/// the user to that transaction in Transaction History. Callers that already
/// live inside Wallet/Transaction History omit it, since navigating there
/// again would be redundant.
void showTransactionDetailSheet(BuildContext context, WalletTransaction txn, {VoidCallback? onTapNavigate}) {
  showAppDialog(
    context,
    builder: (dialogContext) => InkWell(
      onTap: onTapNavigate == null
          ? null
          : () {
              Navigator.pop(dialogContext);
              onTapNavigate();
            },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Align(
              alignment: Alignment.centerRight,
              child: AppDialogCloseButton(),
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
            Divider(color: AppColors.border),
            _kv('Reference No.', txn.referenceNo),
            _kv('Date', formatTxnDate(txn.dateTime)),
            _kv('Time', formatTxnTime(txn.dateTime)),
            _kv('Method', txn.method),
            _kv('Status', 'Completed'),
            if (onTapNavigate != null) ...[
              const SizedBox(height: 8),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Tap to view in Wallet',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                    const SizedBox(width: 4),
                    Icon(CupertinoIcons.chevron_right, size: 14, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ],
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
