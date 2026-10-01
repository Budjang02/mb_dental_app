import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';

import 'billing_receipts.dart';
import 'wallet_history.dart';

/// The wallet ledger and Billing & Receipts, side by side. Billing is what
/// the website keeps under My Records › Billing; the dashboard's Billing
/// action and billing notices open this screen on that tab.
class TransactionHistoryScreen extends StatelessWidget {
  /// Which tab opens first: 0 = Wallet transactions, 1 = Billing & Receipts.
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
              Tab(text: 'Wallet'),
              Tab(text: 'Billing & Receipts'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: Listenable.merge([PatientRepository(), ThemeController()]),
          builder: (context, _) => TabBarView(
            children: [
              RefreshIndicator(
                onRefresh: () => PatientRepository().load(force: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 32),
                  children: const [WalletHistoryCard(plain: true)],
                ),
              ),
              const BillingReceiptsView(),
            ],
          ),
        ),
      ),
    );
  }
}
