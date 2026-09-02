import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/payment.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';
import 'package:mb_dental_app/widgets/transaction_detail_sheet.dart';

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

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
            return const TabBarView(
              children: [
                _TransactionsTab(),
                _BillingTab(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TransactionsTab extends StatelessWidget {
  const _TransactionsTab();

  @override
  Widget build(BuildContext context) {
    final repository = PatientRepository();
    final transactions = repository.transactions;
    if (transactions.isEmpty) {
      return Center(
        child: Text('No transactions yet.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final grouped = <String, List<WalletTransaction>>{};
    for (final t in transactions) {
      grouped.putIfAbsent(formatTxnDate(t.dateTime), () => []).add(t);
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(
              entry.key,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          ),
          for (final txn in entry.value) ...[
            _buildTile(context, txn),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildTile(BuildContext context, WalletTransaction txn) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showTransactionDetailSheet(context, txn),
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
                  Text(txn.title,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    '${txn.subtitle} • ${formatTxnTime(txn.dateTime)}',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              '${txn.isCredit ? '+' : '-'} ₱${txn.amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: txn.isCredit ? AppColors.success : AppColors.error,
              ),
            ),
          ],
        ),
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
                  Text(bill.procedureName,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    '${bill.doctorName} • ${formatBillDate(bill.billedOn)}',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
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
          _kv('Doctor', bill.doctorName),
          _kv('Amount', '₱${bill.amount.toStringAsFixed(2)}'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Status', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text(bill.status,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: AppColors.border),
          const SizedBox(height: 4),
          Text('RECEIPT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1)),
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
