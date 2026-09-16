import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';
import 'package:mb_dental_app/widgets/wallet_txn_widgets.dart';

/// "X" in the top-right corner of the wallet windows: 30px, transparent, rounded.
class WalletCloseButton extends StatelessWidget {
  const WalletCloseButton({super.key});

  @override
  Widget build(BuildContext context) {
    final hover = ThemeController().isDark ? const Color(0xFF253047) : AppColors.background;
    return SizedBox(
      width: 30,
      height: 30,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: hover,
          highlightColor: hover,
          onTap: () => Navigator.pop(context),
          child: Icon(TablerIcons.x, size: 18, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// [onTapNavigate], when given, makes the whole dialog body tappable — used
/// by the Dashboard's Recent Activity so tapping the floating window takes
/// the user to that transaction in the wallet. Callers that already live
/// inside the wallet omit it.
void showTransactionDetailSheet(BuildContext context, WalletTransaction txn, {VoidCallback? onTapNavigate}) {
  final dark = ThemeController().isDark;
  final strong = dark ? const Color(0xFFE2E8F0) : AppColors.textPrimary;
  showAppDialog(
    context,
    maxWidth: 500,
    builder: (dialogContext) => InkWell(
      onTap: onTapNavigate == null
          ? null
          : () {
              Navigator.pop(dialogContext);
              onTapNavigate();
            },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(30, 28, 30, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Transaction Details',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ),
                const WalletCloseButton(),
              ],
            ),
            const SizedBox(height: 20),
            Center(child: WalletTxnIcon(isCredit: txn.isCredit, size: 52, iconSize: 26)),
            const SizedBox(height: 12),
            Text(
              txnDetailTitle(txn),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: strong),
            ),
            const SizedBox(height: 18),
            Divider(height: 1, color: dark ? const Color(0xFF334155) : AppColors.border),
            const SizedBox(height: 8),
            _row('Amount', txnAmountLabel(txn, spaced: false), txn.isCredit ? txnInColor : strong),
            _row('Date & Time', formatTxnDateTime(txn.dateTime), strong),
            _row('Reference Number', walletRef13(txn.referenceNo), strong),
            if (onTapNavigate != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Tap to view in Wallet',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                  const SizedBox(width: 4),
                  Icon(CupertinoIcons.chevron_right, size: 14, color: AppColors.primary),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _row(String label, String value, Color valueColor) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
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
      ],
    ),
  );
}
