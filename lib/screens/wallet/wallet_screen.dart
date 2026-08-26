import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/transaction_detail_sheet.dart';
import 'camera_scan_screen.dart';
import 'transaction_history_screen.dart';

enum _TxnFilter { all, moneyIn, moneyOut }

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final PatientRepository _repository = PatientRepository();
  _TxnFilter _filter = _TxnFilter.all;

  List<WalletTransaction> _applyFilter(List<WalletTransaction> all) {
    switch (_filter) {
      case _TxnFilter.moneyIn:
        return all.where((t) => t.isCredit).toList();
      case _TxnFilter.moneyOut:
        return all.where((t) => !t.isCredit).toList();
      case _TxnFilter.all:
        return all;
    }
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
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionHistoryScreen())),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _repository,
        builder: (context, _) {
          final filtered = _applyFilter(_repository.transactions);
          final grouped = <String, List<WalletTransaction>>{};
          for (final t in filtered) {
            grouped.putIfAbsent(formatTxnDate(t.dateTime), () => []).add(t);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBalanceCard(),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Transactions',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildFilterChips(),
                const SizedBox(height: 16),
                if (grouped.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text('No transactions yet.', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  )
                else
                  for (final entry in grouped.entries) ...[
                    Text(
                      entry.key,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                    const SizedBox(height: 8),
                    for (final txn in entry.value) ...[
                      _buildTransactionTile(txn),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 6),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('Available Balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
              SizedBox(width: 6),
              Icon(CupertinoIcons.eye, color: Colors.white70, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '₱ ${_repository.walletBalance.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(CupertinoIcons.creditcard, color: Colors.white, size: 32),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: () {
                    _repository.addWalletTransaction(
                      title: 'Wallet Top-up',
                      subtitle: 'GCash',
                      amount: 500,
                      type: TransactionType.credit,
                      icon: CupertinoIcons.creditcard,
                      method: 'GCash',
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('₱500.00 added to your wallet.')),
                    );
                  },
                  icon: const Icon(CupertinoIcons.add, size: 18),
                  label: const Text('Add Money', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScanScreen())),
                  icon: const Icon(CupertinoIcons.qrcode_viewfinder, size: 18),
                  label: const Text('Pay / Scan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    Widget chip(String label, _TxnFilter value) {
      final isSelected = _filter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: isSelected,
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          backgroundColor: AppColors.surface,
          side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
          onSelected: (_) => setState(() => _filter = value),
        ),
      );
    }

    return Row(
      children: [
        chip('All', _TxnFilter.all),
        chip('Money In', _TxnFilter.moneyIn),
        chip('Money Out', _TxnFilter.moneyOut),
      ],
    );
  }

  Widget _buildTransactionTile(WalletTransaction txn) {
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
                  Text('${txn.subtitle} • ${formatTxnTime(txn.dateTime)}',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Row(
              children: [
                Text(
                  '${txn.isCredit ? '+' : '-'} ₱${txn.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: txn.isCredit ? AppColors.success : AppColors.error,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(CupertinoIcons.chevron_right, color: AppColors.textSecondary, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
