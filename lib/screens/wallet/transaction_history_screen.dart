import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/transaction_detail_sheet.dart';

class TransactionHistoryScreen extends StatelessWidget {
  const TransactionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = PatientRepository();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Transaction History')),
      body: ListenableBuilder(
        listenable: repository,
        builder: (context, _) {
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
        },
      ),
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
