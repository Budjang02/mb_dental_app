import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/widgets/wallet_txn_widgets.dart';

/// Full-screen receipt for a wallet transaction.
class TransactionDetailScreen extends StatelessWidget {
  final WalletTransaction transaction;

  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final dark = ThemeController().isDark;
    final strong = dark ? const Color(0xFFF1F5F9) : AppColors.textPrimary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Transaction Details')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    WalletTxnIcon(isCredit: transaction.isCredit, size: 56, iconSize: 28),
                    const SizedBox(height: 14),
                    Text(
                      txnDetailTitle(transaction),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: strong),
                    ),
                    const SizedBox(height: 22),
                    Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 8),
                    _DetailRow(
                      label: 'Amount',
                      value: txnAmountLabel(transaction, spaced: false),
                      valueColor: transaction.isCredit ? txnInColor : strong,
                    ),
                    _DetailRow(label: 'Date & Time', value: formatTxnDateTime(transaction.dateTime), valueColor: strong),
                    _DetailRow(
                      label: 'Reference Number',
                      value: walletRef13(transaction.referenceNo),
                      valueColor: strong,
                      trailing: IconButton(
                        tooltip: 'Copy reference number',
                        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                        padding: EdgeInsets.zero,
                        icon: Icon(TablerIcons.copy, size: 19, color: AppColors.primary),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: walletRef13(transaction.referenceNo)));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reference number copied.')));
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final Widget? trailing;

  const _DetailRow({required this.label, required this.value, required this.valueColor, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
  }
}
