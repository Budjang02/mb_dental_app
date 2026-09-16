import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/patient_api.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/wallet_txn_widgets.dart';
import 'cash_in_dialog.dart';
import 'transaction_detail_screen.dart';
import 'transaction_history_screen.dart';
import 'wallet_topup_return.dart';

enum _WalletDateFilter { all, today, last7Days, last30Days, last60Days, last90Days }

enum _WalletTypeFilter { all, moneyIn, moneyOut }

const _walletDateLabels = <_WalletDateFilter, String>{
  _WalletDateFilter.all: 'All Dates',
  _WalletDateFilter.today: 'Today',
  _WalletDateFilter.last7Days: 'Last 7 days',
  _WalletDateFilter.last30Days: 'Last 30 Days',
  _WalletDateFilter.last60Days: 'Last 60 Days',
  _WalletDateFilter.last90Days: 'Last 90 Days',
};

const _walletTypeLabels = <_WalletTypeFilter, String>{
  _WalletTypeFilter.all: 'All Types',
  _WalletTypeFilter.moneyIn: 'Money In',
  _WalletTypeFilter.moneyOut: 'Money Out',
};

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> with WidgetsBindingObserver, WalletTopupReturn {
  final PatientRepository _repository = PatientRepository();
  bool _balanceHidden = false;
  _WalletDateFilter _dateFilter = _WalletDateFilter.all;
  _WalletTypeFilter _typeFilter = _WalletTypeFilter.all;

  Future<void> _openCashIn() async {
    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CashInScreen()));
  }

  List<WalletTransaction> _filteredTransactions(List<WalletTransaction> transactions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return transactions.where((transaction) {
      final transactionDate = transaction.dateTime.toLocal();
      final day = DateTime(transactionDate.year, transactionDate.month, transactionDate.day);
      final daysAgo = today.difference(day).inDays;
      final dateMatches = switch (_dateFilter) {
        _WalletDateFilter.all => true,
        _WalletDateFilter.today => daysAgo == 0,
        _WalletDateFilter.last7Days => daysAgo >= 0 && daysAgo < 7,
        _WalletDateFilter.last30Days => daysAgo >= 0 && daysAgo < 30,
        _WalletDateFilter.last60Days => daysAgo >= 0 && daysAgo < 60,
        _WalletDateFilter.last90Days => daysAgo >= 0 && daysAgo < 90,
      };
      if (!dateMatches) return false;
      return switch (_typeFilter) {
        _WalletTypeFilter.all => true,
        _WalletTypeFilter.moneyIn => transaction.isCredit,
        _WalletTypeFilter.moneyOut => !transaction.isCredit,
      };
    }).toList();
  }

  Future<void> _selectDateFilter() async {
    final selected = await _showFilterSheet<_WalletDateFilter>('Select Date Range', _dateFilter, _walletDateLabels);
    if (selected != null && mounted) setState(() => _dateFilter = selected);
  }

  Future<void> _selectTypeFilter() async {
    final selected = await _showFilterSheet<_WalletTypeFilter>('Select Type', _typeFilter, _walletTypeLabels);
    if (selected != null && mounted) setState(() => _typeFilter = selected);
  }

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
                  Expanded(child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary))),
                  IconButton(onPressed: () => Navigator.pop(sheetContext), icon: Icon(Icons.close, color: AppColors.textSecondary)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Wallet'),
        actions: [
          IconButton(
            icon: Icon(CupertinoIcons.clock, color: AppColors.textPrimary),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionHistoryScreen())),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_repository, ThemeController()]),
        builder: (context, _) {
          return RefreshIndicator(
            onRefresh: () => _repository.load(force: true),
            edgeOffset: 12,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 104),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (topupBanner != null) ...[_buildTopupBanner(topupBanner!), const SizedBox(height: 16)],
                  _buildBalanceCard(),
                  const SizedBox(height: 24),
                  _buildHistoryCard(_filteredTransactions(_repository.transactions)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopupBanner(TopupBanner banner) {
    final color = switch (banner.kind) {
      TopupBannerKind.paid => txnInColor,
      TopupBannerKind.failed => AppColors.error,
      TopupBannerKind.pending => AppColors.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          if (banner.busy)
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
          else
            Icon(
              banner.kind == TopupBannerKind.paid
                  ? TablerIcons.circle_check
                  : banner.kind == TopupBannerKind.failed
                  ? TablerIcons.alert_circle
                  : TablerIcons.clock,
              size: 18,
              color: color,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              banner.message,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            // Lighter teal wash in light mode so the card reads as a bright
            // panel on the pale page rather than a dark slab.
            colors: ThemeController().isDark
                ? const [Color(0xFF0C4A43), Color(0xFF1B8C7C), Color(0xFF0D5B52)]
                : const [Color(0xFF12796D), Color(0xFF23A793), Color(0xFF158A7B)],
            stops: const [0.0, 0.58, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Oversized soft circle bleeding off the right edge, as in the
            // reference artwork.
            Positioned(
              right: -70,
              top: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.07)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Available Balance',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => setState(() => _balanceHidden = !_balanceHidden),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            _balanceHidden ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _balanceHidden ? '₱ ••••••' : formatPeso(_repository.walletBalance),
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0C4A43),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: _openCashIn,
                      icon: const Icon(TablerIcons.plus, size: 18),
                      label: const Text('Cash In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(List<WalletTransaction> rows) {
    final grouped = <String, List<WalletTransaction>>{};
    for (final t in rows) {
      grouped.putIfAbsent(formatTxnMonth(t.dateTime.toLocal()), () => []).add(t);
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transaction History',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _historyFilterButton(_walletDateLabels[_dateFilter]!, _selectDateFilter),
                      const SizedBox(width: 8),
                      _historyFilterButton(_walletTypeLabels[_typeFilter]!, _selectTypeFilter),
                    ],
                  ),
                ],
              ),
            ),
            if (grouped.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 36),
                child: Text(
                  _emptyMessage(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              for (final entry in grouped.entries) ...[
                TxnMonthHeader(entry.key),
                for (final txn in entry.value)
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
      ),
    );
  }

  String _emptyMessage() {
    if (PatientApi.walletUnavailable) {
      return 'The wallet is not set up on the clinic\'s system yet. Your transactions will appear here once it is.';
    }
    return 'No transactions yet. Cash in to get started.';
  }

  Widget _historyFilterButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
