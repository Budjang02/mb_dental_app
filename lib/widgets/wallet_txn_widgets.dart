import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/wallet_topup_api.dart';

// Everything here mirrors js/patient-wallet.js, so a ledger row reads, looks
// and is numbered the same on the website and in the app.

const List<String> _monthLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// [d] as a wall-clock time in Asia/Manila (UTC+8, no daylight saving), so a
/// transaction shows the clinic's date and time whatever the phone's zone.
DateTime manilaTime(DateTime d) => d.toUtc().add(const Duration(hours: 8));

/// "September 2026" — the month band above a group of rows.
String formatTxnMonth(DateTime d) {
  final m = manilaTime(d);
  return '${_monthLong[m.month - 1]} ${m.year}';
}

/// "16 September 2026" — the date under a row's title.
String formatTxnDay(DateTime d) {
  final m = manilaTime(d);
  return '${m.day} ${_monthLong[m.month - 1]} ${m.year}';
}

/// "Sep 16, 2026, 11:40 AM" — the details window.
String formatTxnDateTime(DateTime d) {
  final m = manilaTime(d);
  final hour = m.hour % 12 == 0 ? 12 : m.hour % 12;
  final minute = m.minute.toString().padLeft(2, '0');
  final period = m.hour >= 12 ? 'PM' : 'AM';
  return '${_monthLong[m.month - 1].substring(0, 3)} ${m.day}, ${m.year}, $hour:$minute $period';
}

/// The website's `_walletRef13`: a 13-digit display number derived from the
/// stored reference with 64-bit FNV-1a, so the same transaction shows the same
/// number on both. Display only; the stored `reference_no` is unchanged.
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

/// The rail spelled one way (`gcash` and `GCash` are the same), or empty for
/// none / the wallet itself.
String txnRailLabel(WalletTransaction txn) {
  final raw = txn.method.trim();
  if (raw.isEmpty || raw.toLowerCase() == 'wallet') return '';
  for (final rail in kCashInRails) {
    if (raw.toLowerCase() == rail.id || raw.toLowerCase() == rail.label.toLowerCase()) return rail.label;
  }
  return raw;
}

/// Row and details title (`_walletTitle`).
String txnTitle(WalletTransaction txn) {
  switch (txn.kind) {
    case WalletTxnKind.adjust:
      return 'Wallet Adjustment';
    case WalletTxnKind.refund:
      return 'Refund';
    case WalletTxnKind.debit:
      return RegExp('appointment', caseSensitive: false).hasMatch(txn.description)
          ? 'Appointment Downpayment'
          : 'Wallet Payment';
    case WalletTxnKind.credit:
      final rail = txnRailLabel(txn);
      return rail.isEmpty ? 'Cash In' : 'Cash in from $rail';
  }
}

/// "Payment Method" in the details (`_walletMethodLabel`).
String txnMethodLabel(WalletTransaction txn) {
  final rail = txnRailLabel(txn);
  switch (txn.kind) {
    case WalletTxnKind.debit:
      return 'Wallet Balance';
    case WalletTxnKind.credit:
      return rail.isEmpty ? 'Cash In' : 'Cash In from $rail';
    case WalletTxnKind.refund:
    case WalletTxnKind.adjust:
      return rail.isEmpty ? 'Wallet Balance' : rail;
  }
}

/// The sentence under the details (`_walletNote`).
String txnNote(WalletTransaction txn) {
  final rail = txnRailLabel(txn);
  switch (txn.kind) {
    case WalletTxnKind.debit:
      return 'Deducted from your wallet balance.';
    case WalletTxnKind.refund:
      return 'Returned to your wallet balance.';
    case WalletTxnKind.adjust:
      return 'Adjusted by the clinic.';
    case WalletTxnKind.credit:
      return 'Added to your wallet balance${rail.isEmpty ? '' : ' from $rail'}.';
  }
}

/// `+ ₱1,000.00` / `− ₱500.00`, full precision.
String txnAmountLabel(WalletTransaction txn, {bool spaced = true}) {
  final gap = spaced ? ' ' : '';
  return '${txn.isCredit ? '+' : '−'}$gap${formatPeso(txn.amount)}';
}

/// Amounts are neutral — navy in light mode, white in dark. The icon alone
/// carries the direction's colour.
Color get txnAmountColor => ThemeController().isDark ? Colors.white : const Color(0xFF0F172A);

/// Kept for callers outside the wallet (the cash-in banner).
Color get txnInColor => const Color(0xFF16A34A);

/// Icon colour and tile for a kind (`.wtx-tone-*`, light and dark).
(Color, Color) txnTone(WalletTxnKind kind) {
  final dark = ThemeController().isDark;
  return switch (kind) {
    WalletTxnKind.credit || WalletTxnKind.refund => dark
        ? (const Color(0xFF86EFAC), const Color(0xFF22C55E).withValues(alpha: 0.16))
        : (const Color(0xFF15803D), const Color(0xFF22C55E).withValues(alpha: 0.12)),
    WalletTxnKind.debit => dark
        ? (const Color(0xFFFDA4AF), const Color(0xFFF43F5E).withValues(alpha: 0.16))
        : (const Color(0xFFBE123C), const Color(0xFFF43F5E).withValues(alpha: 0.11)),
    WalletTxnKind.adjust => dark
        ? (const Color(0xFFCBD5E1), const Color(0xFF94A3B8).withValues(alpha: 0.16))
        : (const Color(0xFF475569), const Color(0xFF64748B).withValues(alpha: 0.12)),
  };
}

/// The website's outline icons from js/icons.js (Tabler geometry), drawn
/// from the same paths.
enum WalletGlyph { wallet, walletPlus, walletMinus, plus, check }

const String _walletBody =
    '<path d="M17 8v-3a1 1 0 0 0 -1 -1h-10a2 2 0 0 0 0 4h12a1 1 0 0 1 1 1v3m0 4v3a1 1 0 0 1 -1 1h-12a2 2 0 0 1 -2 -2v-12" />'
    '<path d="M20 12v4h-4a2 2 0 0 1 0 -4h4" />';

String _glyphPaths(WalletGlyph glyph) => switch (glyph) {
      WalletGlyph.wallet => _walletBody,
      WalletGlyph.walletPlus => '$_walletBody<path d="M7 14h4m-2 -2v4" />',
      WalletGlyph.walletMinus => '$_walletBody<path d="M7 14h4" />',
      WalletGlyph.plus => '<path d="M12 5l0 14" /><path d="M5 12l14 0" />',
      WalletGlyph.check => '<path d="M5 12l5 5l10 -10" />',
    };

class WalletGlyphIcon extends StatelessWidget {
  final WalletGlyph glyph;
  final double size;
  final Color color;

  const WalletGlyphIcon(this.glyph, {super.key, this.size = 20, required this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
      'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${_glyphPaths(glyph)}</svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

/// The tinted tile with wallet-plus (money in) or wallet-minus (money out).
class WalletTxnIcon extends StatelessWidget {
  final WalletTransaction txn;
  final double size;
  final double iconSize;

  const WalletTxnIcon({super.key, required this.txn, this.size = 38, this.iconSize = 20});

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = txnTone(txn.kind);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.28)),
      child: WalletGlyphIcon(txn.isCredit ? WalletGlyph.walletPlus : WalletGlyph.walletMinus,
          size: iconSize, color: fg),
    );
  }
}

/// Light band naming the month above its rows.
class TxnMonthHeader extends StatelessWidget {
  final String label;

  const TxnMonthHeader(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final dark = ThemeController().isDark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0F172A) : AppColors.background,
        border: Border.symmetric(horizontal: BorderSide(color: AppColors.border)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
      ),
    );
  }
}

/// One ledger row: icon, title, date (and "Wallet Balance" for money out),
/// signed amount on the right. The whole row opens its details.
class WalletTxnRow extends StatelessWidget {
  final WalletTransaction txn;
  final VoidCallback onTap;

  const WalletTxnRow({super.key, required this.txn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sub = [formatTxnDay(txn.dateTime), if (!txn.isCredit) 'Wallet Balance'].join(' · ');
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                WalletTxnIcon(txn: txn),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        txnTitle(txn),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(sub, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  txnAmountLabel(txn),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: txnAmountColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Filters (the website's WALLET_RANGES and pills) ---

enum WalletRange { all, today, last7, last30, last60, last90 }

enum WalletDirection { all, moneyIn, moneyOut }

const walletRangeLabels = <WalletRange, String>{
  WalletRange.all: 'All Dates',
  WalletRange.today: 'Today',
  WalletRange.last7: 'Last 7 Days',
  WalletRange.last30: 'Last 30 Days',
  WalletRange.last60: 'Last 60 Days',
  WalletRange.last90: 'Last 90 Days',
};

const walletDirectionLabels = <WalletDirection, String>{
  WalletDirection.all: 'All',
  WalletDirection.moneyIn: 'Money In',
  WalletDirection.moneyOut: 'Money Out',
};

/// `_walletInRange`: "Today" from Manila midnight; "Last N Days" a rolling
/// N×24 hours back from now.
bool walletInRange(WalletTransaction txn, WalletRange range, {DateTime? now}) {
  final clock = (now ?? DateTime.now()).toUtc();
  final at = txn.dateTime.toUtc();
  switch (range) {
    case WalletRange.all:
      return true;
    case WalletRange.today:
      final m = manilaTime(clock);
      final manilaMidnight = DateTime.utc(m.year, m.month, m.day).subtract(const Duration(hours: 8));
      return !at.isBefore(manilaMidnight);
    case WalletRange.last7:
      return !at.isBefore(clock.subtract(const Duration(days: 7)));
    case WalletRange.last30:
      return !at.isBefore(clock.subtract(const Duration(days: 30)));
    case WalletRange.last60:
      return !at.isBefore(clock.subtract(const Duration(days: 60)));
    case WalletRange.last90:
      return !at.isBefore(clock.subtract(const Duration(days: 90)));
  }
}

bool walletMatchesDirection(WalletTransaction txn, WalletDirection direction) => switch (direction) {
      WalletDirection.all => true,
      WalletDirection.moneyIn => txn.isCredit,
      WalletDirection.moneyOut => !txn.isCredit,
    };

/// The website's empty-history wording for the current filters.
String walletEmptyMessage(WalletRange range, WalletDirection direction) {
  if (range != WalletRange.all) return 'No transactions in this period.';
  return switch (direction) {
    WalletDirection.moneyIn => 'No cash-ins yet.',
    WalletDirection.moneyOut => 'Nothing paid from the wallet yet.',
    WalletDirection.all => 'No transactions yet. Cash in to get started.',
  };
}
