import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/widgets/wallet_txn_widgets.dart';

/// Transaction Details for one ledger row — the website's `openWalletTxn`:
/// icon and title, signed amount, payment method, description, date and time
/// in Manila, the 13-digit reference, and what it did to the balance.
class TransactionDetailScreen extends StatelessWidget {
  final WalletTransaction transaction;

  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    ThemeController();
    final t = transaction;
    final (tone, _) = txnTone(t.kind);
    final description = t.description.trim();
    final ref = walletRef13(t.referenceNo);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Transaction Details')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                WalletTxnIcon(txn: t, size: 56, iconSize: 28),
                const SizedBox(height: 14),
                Text(
                  txnTitle(t),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 20),
                Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 6),
                _Row('Amount', txnAmountLabel(t)),
                _Row('Payment Method', txnMethodLabel(t)),
                if (description.isNotEmpty) _Row('Description', description),
                _Row('Date & Time', formatTxnDateTime(t.dateTime)),
                _Row(
                  'Reference Number',
                  ref,
                  trailing: ref == '—'
                      ? null
                      : IconButton(
                          tooltip: 'Copy reference number',
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          padding: EdgeInsets.zero,
                          icon: Icon(TablerIcons.copy, size: 19, color: AppColors.primary),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: ref));
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(content: Text('Reference number copied.')));
                          },
                        ),
                ),
                const SizedBox(height: 12),
                Text(
                  txnNote(t),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tone),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;

  const _Row(this.label, this.value, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
  }
}
