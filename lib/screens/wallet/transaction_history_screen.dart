import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/payment.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';
import 'package:mb_dental_app/widgets/wallet_txn_widgets.dart';
import 'transaction_detail_screen.dart';

const List<String> _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatBillDate(DateTime date) => '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';

Color _billingStatusColor(String status) => status == 'Paid' ? AppColors.success : AppColors.warning;

class TransactionHistoryScreen extends StatelessWidget {
  /// Which tab opens first: 0 = Transactions, 1 = Billing. The dashboard's
  /// Billing quick action jumps straight to the billing statements.
  final int initialTabIndex;

  const TransactionHistoryScreen({super.key, this.initialTabIndex = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTabIndex,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Transaction History'),
          bottom: TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Transactions'),
              Tab(text: 'Billing'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: Listenable.merge([PatientRepository(), ThemeController()]),
          builder: (context, _) {
            return const TabBarView(children: [_TransactionsTab(), _BillingTab()]);
          },
        ),
      ),
    );
  }
}

enum _HistoryDateFilter { all, today, last7Days, last30Days, last60Days, last90Days }

enum _HistoryTypeFilter { all, moneyIn, moneyOut }

const _historyDateLabels = <_HistoryDateFilter, String>{
  _HistoryDateFilter.all: 'All Dates',
  _HistoryDateFilter.today: 'Today',
  _HistoryDateFilter.last7Days: 'Last 7 days',
  _HistoryDateFilter.last30Days: 'Last 30 Days',
  _HistoryDateFilter.last60Days: 'Last 60 Days',
  _HistoryDateFilter.last90Days: 'Last 90 Days',
};

const _historyTypeLabels = <_HistoryTypeFilter, String>{
  _HistoryTypeFilter.all: 'All Types',
  _HistoryTypeFilter.moneyIn: 'Money In',
  _HistoryTypeFilter.moneyOut: 'Money Out',
};

class _TransactionsTab extends StatefulWidget {
  const _TransactionsTab();

  @override
  State<_TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<_TransactionsTab> {
  _HistoryDateFilter _dateFilter = _HistoryDateFilter.all;
  _HistoryTypeFilter _typeFilter = _HistoryTypeFilter.all;

  bool _matchesDate(WalletTransaction transaction) {
    if (_dateFilter == _HistoryDateFilter.all) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = transaction.dateTime.toLocal();
    final transactionDay = DateTime(date.year, date.month, date.day);
    final days = today.difference(transactionDay).inDays;
    return switch (_dateFilter) {
      _HistoryDateFilter.all => true,
      _HistoryDateFilter.today => days == 0,
      _HistoryDateFilter.last7Days => days >= 0 && days < 7,
      _HistoryDateFilter.last30Days => days >= 0 && days < 30,
      _HistoryDateFilter.last60Days => days >= 0 && days < 60,
      _HistoryDateFilter.last90Days => days >= 0 && days < 90,
    };
  }

  List<WalletTransaction> _filtered(List<WalletTransaction> transactions) {
    return transactions.where((transaction) {
      if (!_matchesDate(transaction)) return false;
      return switch (_typeFilter) {
        _HistoryTypeFilter.all => true,
        _HistoryTypeFilter.moneyIn => transaction.isCredit,
        _HistoryTypeFilter.moneyOut => !transaction.isCredit,
      };
    }).toList();
  }

  Future<void> _selectDate() async {
    final result = await _showSelector<_HistoryDateFilter>(
      title: 'Select Date Range',
      selected: _dateFilter,
      labels: _historyDateLabels,
    );
    if (result != null && mounted) setState(() => _dateFilter = result);
  }

  Future<void> _selectType() async {
    final result = await _showSelector<_HistoryTypeFilter>(
      title: 'Select Type',
      selected: _typeFilter,
      labels: _historyTypeLabels,
    );
    if (result != null && mounted) setState(() => _typeFilter = result);
  }

  Future<T?> _showSelector<T>({required String title, required T selected, required Map<T, String> labels}) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 8, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
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
                      fontSize: 16,
                      color: entry.key == selected ? AppColors.primary : AppColors.textPrimary,
                      fontWeight: entry.key == selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: entry.key == selected ? Icon(Icons.check, color: AppColors.primary) : null,
                  onTap: () => Navigator.pop(sheetContext, entry.key),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = PatientRepository();
    final transactions = _filtered(repository.transactions);

    final grouped = <String, List<WalletTransaction>>{};
    for (final t in transactions) {
      grouped.putIfAbsent(formatTxnMonth(t.dateTime.toLocal()), () => []).add(t);
    }

    return Column(
      children: [
        _FilterBar(
          dateLabel: _historyDateLabels[_dateFilter]!,
          typeLabel: _historyTypeLabels[_typeFilter]!,
          onDateTap: _selectDate,
          onTypeTap: _selectType,
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF1E293B),
            child: RefreshIndicator(
              edgeOffset: 12,
              onRefresh: () => repository.load(force: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  if (grouped.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 36, 20, 48),
                      child: Text(
                        repository.transactions.isEmpty
                            ? 'No transactions yet. Cash in to get started.'
                            : 'No transactions match these filters.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF94A3B8)),
                      ),
                    )
                  else
                    for (final entry in grouped.entries) ...[
                      TxnMonthHeader(entry.key, darkSurface: true),
                      for (final txn in entry.value)
                        WalletTxnRow(
                          txn: txn,
                          darkSurface: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: txn)),
                          ),
                        ),
                    ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String dateLabel;
  final String typeLabel;
  final VoidCallback onDateTap;
  final VoidCallback onTypeTap;

  const _FilterBar({required this.dateLabel, required this.typeLabel, required this.onDateTap, required this.onTypeTap});

  @override
  Widget build(BuildContext context) {
    Widget selector(String label, VoidCallback onTap) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(width: 3),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );

    return Container(
      color: AppColors.surface,
      child: Row(
        children: [
          const SizedBox(width: 16),
          selector(dateLabel, onDateTap),
          const SizedBox(width: 8),
          selector(typeLabel, onTypeTap),
        ],
      ),
    );
  }
}

class _BillingTab extends StatelessWidget {
  const _BillingTab();

  @override
  Widget build(BuildContext context) {
    final billing = PatientRepository().billing;
    if (billing.isEmpty) {
      return Center(
        child: Text('No billing records yet.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final sorted = List<Payment>.from(billing)..sort((a, b) => b.billedOn.compareTo(a.billedOn));

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildBillingTile(context, sorted[index]),
    );
  }

  Widget _buildBillingTile(BuildContext context, Payment bill) {
    final statusColor = _billingStatusColor(bill.status);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showBillingDetailDialog(context, bill),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bill.procedureName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(kDoctorIcon, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '${doctorLabel(bill.doctorName)} • ${formatBillDate(bill.billedOn)}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₱${bill.amount.toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    bill.status,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating window for a billing record: the requested summary line (Date,
/// Procedure, Doctor, Amount, Status) up top, and the receipt-only details
/// (reference no., payment method, clinic) below — nothing from the summary
/// is repeated down there.
void _showBillingDetailDialog(BuildContext context, Payment bill) {
  final statusColor = _billingStatusColor(bill.status);
  showAppDialog(
    context,
    builder: (dialogContext) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  bill.procedureName,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
              ),
              const AppDialogCloseButton(),
            ],
          ),
          const SizedBox(height: 16),
          _kv('Date', formatBillDate(bill.billedOn)),
          _kv('Procedure', bill.procedureName),
          _kv('Doctor', doctorLabel(bill.doctorName)),
          _kv('Amount', '₱${bill.amount.toStringAsFixed(2)}'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Status', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    bill.status,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: AppColors.border),
          const SizedBox(height: 4),
          Text(
            'RECEIPT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          _kv('Reference No.', bill.referenceNo),
          _kv('Clinic', 'Mariano & Bolasoc Dental Center'),
          _kv('Payment Method', bill.paymentMethod ?? 'Not yet paid'),
        ],
      ),
    ),
  );
}

Widget _kv(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ),
      ],
    ),
  );
}
