import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/load_state.dart';
import 'package:mb_dental_app/repositories/patient_api.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/section_states.dart';
import 'package:mb_dental_app/widgets/wallet_txn_widgets.dart';

import 'transaction_detail_screen.dart';

/// The wallet's Transaction History: date range, All / Money In / Money Out,
/// rows newest first under month-and-year headings. Every row is a real
/// `wallet_transactions` row; tapping one opens its details.
class WalletHistoryCard extends StatefulWidget {
  /// No card and no "Transaction History" title: the filters and the list
  /// fill the screen, as in Transaction History › Wallet.
  final bool plain;

  const WalletHistoryCard({super.key, this.plain = false});

  @override
  State<WalletHistoryCard> createState() => _WalletHistoryCardState();
}

class _WalletHistoryCardState extends State<WalletHistoryCard> {
  WalletRange _range = WalletRange.all;
  WalletDirection _direction = WalletDirection.all;

  Future<T?> _showFilterSheet<T>(String title, T current, Map<T, String> labels) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.border),
            for (final entry in labels.entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(
                  entry.value,
                  style: TextStyle(
                    color: entry.key == current ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: entry.key == current ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                trailing: entry.key == current ? Icon(Icons.check, color: AppColors.primary) : null,
                onTap: () => Navigator.pop(sheetContext, entry.key),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRange() async {
    final picked = await _showFilterSheet('Select Date Range', _range, walletRangeLabels);
    if (picked != null && mounted) setState(() => _range = picked);
  }

  Future<void> _pickDirection() async {
    final picked = await _showFilterSheet('Select Type', _direction, _typeLabels);
    if (picked != null && mounted) setState(() => _direction = picked);
  }

  static const _typeLabels = <WalletDirection, String>{
    WalletDirection.all: 'All Types',
    WalletDirection.moneyIn: 'Money In',
    WalletDirection.moneyOut: 'Money Out',
  };

  /// Plain text with a caret, no button chrome — the filter row the wallet
  /// had before.
  Widget _filterButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = PatientRepository();
    final status = repository.effectiveStatusOf(SyncSection.wallet);
    final rows = [
      for (final t in repository.transactions)
        if (walletMatchesDirection(t, _direction) && walletInRange(t, _range)) t,
    ];
    final groups = <(String, List<WalletTransaction>)>[];
    for (final t in rows) {
      final month = formatTxnMonth(t.dateTime);
      if (groups.isEmpty || groups.last.$1 != month) groups.add((month, []));
      groups.last.$2.add(t);
    }

    return Container(
      clipBehavior: widget.plain ? Clip.none : Clip.antiAlias,
      decoration: widget.plain
          ? null
          : BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.plain) ...[
                  Text(
                    'Transaction History',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(child: _filterButton(walletRangeLabels[_range]!, _pickRange)),
                    const SizedBox(width: 16),
                    Expanded(child: _filterButton(_typeLabels[_direction]!, _pickDirection)),
                  ],
                ),
              ],
            ),
          ),
          if (status.hasFailed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SectionErrorNotice(
                status: status,
                compact: true,
                isRetrying: repository.isRetrying(SyncSection.wallet),
                onRetry: () => repository.retrySection(SyncSection.wallet),
              ),
            )
          else if (rows.isEmpty && status.isPending)
            const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 12), child: SectionSkeleton(rows: 2))
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 36),
              child: Column(
                children: [
                  FaIcon(FontAwesomeIcons.receipt, size: 26, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                  const SizedBox(height: 10),
                  Text(
                    PatientApi.walletUnavailable
                        ? "The wallet is not set up on this clinic's database yet."
                        : walletEmptyMessage(_range, _direction),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          else
            for (final (month, items) in groups) ...[
              TxnMonthHeader(month),
              for (final txn in items)
                WalletTxnRow(
                  txn: txn,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: txn)),
                  ),
                ),
            ],
        ],
      ),
    );
  }
}
