import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
import 'package:mb_dental_app/widgets/transaction_detail_sheet.dart';
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
  bool _balanceHidden = false;

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
        listenable: Listenable.merge([_repository, ThemeController()]),
        builder: (context, _) {
          final filtered = _applyFilter(_repository.transactions);
          final grouped = <String, List<WalletTransaction>>{};
          for (final t in filtered) {
            grouped.putIfAbsent(formatTxnDate(t.dateTime), () => []).add(t);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 104),
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

  /// Preset amounts plus a free-entry field, and the funding source to draw
  /// from. Mock only: a real build hands off to the payment gateway here and
  /// credits the wallet on its callback.
  void _showTopUpSheet() {
    // The website's quick amounts and its fixed method list, value for value.
    // The first method, GCash, is the default.
    const presets = <double>[500, 1000, 2000, 5000];
    const methods = <(String, IconData)>[
      ('GCash', CupertinoIcons.device_phone_portrait),
      ('Maya', CupertinoIcons.device_phone_portrait),
      ('Card', CupertinoIcons.creditcard),
      ('Bank Transfer', CupertinoIcons.building_2_fill),
      ('Cash', CupertinoIcons.money_dollar),
    ];

    double? amount = 500;
    var method = methods.first.$1;
    final customController = TextEditingController();
    final referenceController = TextEditingController();

    showAppDialog(
      context,
      maxWidth: 400,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setSheetState) {
          void chooseCustom(String raw) {
            final parsed = double.tryParse(raw.replaceAll(',', '').trim());
            setSheetState(() => amount = (parsed != null && parsed > 0) ? parsed : null);
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Add Money',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const AppDialogCloseButton(),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Choose an amount to load into your wallet.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in presets)
                      _amountChip(
                        label: formatPeso(preset),
                        isSelected: amount == preset && customController.text.trim().isEmpty,
                        onTap: () => setSheetState(() {
                          amount = preset;
                          customController.clear();
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: customController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppColors.textPrimary),
                  onChanged: chooseCustom,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Or enter another amount',
                    hintStyle: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    prefixText: '₱ ',
                    prefixStyle: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                    fillColor: AppColors.background,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Fund From',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                for (final entry in methods) ...[
                  _methodRow(
                    label: entry.$1,
                    icon: entry.$2,
                    isSelected: method == entry.$1,
                    onTap: () => setSheetState(() => method = entry.$1),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 6),
                TextField(
                  controller: referenceController,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Reference no. (optional)',
                    hintStyle: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    fillColor: AppColors.background,
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: amount == null
                      ? null
                      : () async {
                          final credited = amount!;
                          final source = method;
                          final typedReference = referenceController.text.trim();
                          Navigator.pop(dialogContext);
                          try {
                            await _repository.addWalletTransaction(
                              title: 'Wallet Top-up',
                              subtitle: source,
                              amount: credited,
                              type: TransactionType.credit,
                              icon: CupertinoIcons.creditcard,
                              method: source,
                              reference: typedReference.isEmpty ? null : typedReference,
                            );
                          } catch (e) {
                            if (!mounted) return;
                            showAppToast(context, 'The top-up did not go through. Please try again.',
                                isError: true);
                            return;
                          }
                          if (!mounted) return;
                          showAppToast(context, '${formatPeso(credited)} added to your wallet.');
                        },
                  child: Text(amount == null ? 'Enter an amount' : 'Add ${formatPeso(amount!)}'),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      customController.dispose();
      referenceController.dispose();
    });
  }

  Widget _amountChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? AppColors.primary : AppColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _methodRow({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withOpacity(0.08) : AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Icon(
                isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                size: 19,
                color: isSelected ? AppColors.primary : AppColors.border,
              ),
            ],
          ),
        ),
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
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.07),
                ),
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
                        'AVAILABLE BALANCE',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
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
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0C4A43),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            minimumSize: const Size(0, 44),
                          ),
                          onPressed: _showTopUpSheet,
                          icon: const Icon(CupertinoIcons.add, size: 18),
                          label: const Text('Add Money', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),

                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
          showCheckmark: false,
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
