import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/wallet_topup_api.dart';

const List<String> _monthLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "September 2026" — the month band above a group of rows.
String formatTxnMonth(DateTime d) => '${_monthLong[d.month - 1]} ${d.year}';

/// "16 September 2026" — the second line of a row.
String formatTxnDay(DateTime d) => '${d.day} ${_monthLong[d.month - 1]} ${d.year}';

/// "Sep 16, 2026, 11:40 AM" — the details window.
String formatTxnDateTime(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final period = d.hour >= 12 ? 'PM' : 'AM';
  return '${_monthLong[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}, $hour:$minute $period';
}

/// A 13-digit display number derived from the stored reference with 64-bit
/// FNV-1a, so the same transaction always shows the same number. Display
/// only; the stored `reference_no` is unchanged.
String walletRef13(String? ref) {
  if (ref == null || ref.isEmpty) return '—';
  final mask = (BigInt.one << 64) - BigInt.one;
  final prime = BigInt.parse('100000001b3', radix: 16);
  var h = BigInt.parse('cbf29ce484222325', radix: 16);
  for (final rune in ref.runes) {
    h = ((h ^ BigInt.from(rune)) * prime) & mask;
  }
  return (h % BigInt.from(10000000000000)).toString().padLeft(13, '0');
}

String _cashInTitle(WalletTransaction txn) {
  final method = txn.method.trim().toLowerCase();
  if (method.isEmpty) return 'Cash In';
  for (final rail in kCashInRails) {
    if (method == rail.id || method == rail.label.toLowerCase()) return 'Cash in from ${rail.label}';
  }
  return 'Cash In';
}

String txnRowTitle(WalletTransaction txn) => txn.isCredit ? _cashInTitle(txn) : 'Payment';

String txnDetailTitle(WalletTransaction txn) {
  if (txn.isCredit) return _cashInTitle(txn);
  return txn.title.toLowerCase().contains('appointment') ? 'Appointment Downpayment' : 'Payment';
}

/// Green in both themes, lighter on the dark card.
Color get txnInColor => ThemeController().isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);

String txnAmountLabel(WalletTransaction txn, {bool spaced = true}) {
  final gap = spaced ? ' ' : '';
  return '${txn.isCredit ? '+' : '−'}$gap${formatPeso(txn.amount)}';
}

/// Rounded square with a wallet outline and a round plus/minus badge.
class WalletTxnIcon extends StatelessWidget {
  final bool isCredit;
  final double size;
  final double iconSize;

  const WalletTxnIcon({super.key, required this.isCredit, this.size = 38, this.iconSize = 20});

  @override
  Widget build(BuildContext context) {
    final color = isCredit ? const Color(0xFF16A34A) : const Color(0xFF6366F1);
    final tint = isCredit ? const Color(0x1F22C55E) : const Color(0x1F6366F1);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(size * 0.28)),
            child: Icon(TablerIcons.wallet, size: iconSize, color: color),
          ),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.surface, spreadRadius: 2)],
              ),
              child: Icon(isCredit ? TablerIcons.plus : TablerIcons.minus, size: 11, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Light band naming the month above its rows.
class TxnMonthHeader extends StatelessWidget {
  final String label;
  final bool darkSurface;

  const TxnMonthHeader(this.label, {super.key, this.darkSurface = false});

  @override
  Widget build(BuildContext context) {
    final dark = ThemeController().isDark || darkSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0F172A) : AppColors.background,
        border: Border.symmetric(horizontal: BorderSide(color: AppColors.border)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: dark ? const Color(0xFFE2E8F0) : AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// One ledger row: icon, title, date, amount. The whole row is the tap target.
class WalletTxnRow extends StatelessWidget {
  final WalletTransaction txn;
  final VoidCallback onTap;
  final bool darkSurface;

  const WalletTxnRow({super.key, required this.txn, required this.onTap, this.darkSurface = false});

  @override
  Widget build(BuildContext context) {
    final useDarkSurface = ThemeController().isDark || darkSurface;
    final hover = useDarkSurface ? const Color(0xFF253047) : AppColors.background;
    final primaryText = useDarkSurface ? const Color(0xFFF1F5F9) : AppColors.textPrimary;
    final secondaryText = useDarkSurface ? const Color(0xFF94A3B8) : AppColors.textSecondary;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        hoverColor: hover,
        highlightColor: hover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              WalletTxnIcon(isCredit: txn.isCredit),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      txnRowTitle(txn),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryText),
                    ),
                    const SizedBox(height: 2),
                    Text(formatTxnDay(txn.dateTime), style: TextStyle(fontSize: 12, color: secondaryText)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                txnAmountLabel(txn),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: txn.isCredit ? txnInColor : primaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
