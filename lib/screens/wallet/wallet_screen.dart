import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Wallet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: AppColors.textPrimary),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wallet Primary Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Text(
                        'Available Balance',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.visibility_outlined,
                          color: Colors.white70, size: 16),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            '₱ 1,500.00',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Wallet ID: WAL-2026-000123',
                            style:
                            TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_outlined,
                          color: Colors.white,
                          size: 32,
                        ),
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
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            minimumSize: const Size(0, 44),
                          ),
                          onPressed: () {},
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text(
                            'Add Money',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            minimumSize: const Size(0, 44),
                          ),
                          onPressed: () {},
                          icon: const Icon(Icons.qr_code_scanner, size: 18),
                          label: const Text(
                            'Pay / Scan',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Recent Transactions Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Transactions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: const [
                      Text(
                        'All Transactions',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down,
                          size: 16, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Date Group: Today - Aug 23, 2026
            const Text(
              'Today - Aug 23, 2026',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            _buildTransactionTile(
              icon: Icons.clean_hands_outlined,
              title: 'Dental Cleaning',
              subtitle: 'Payment\n10:15 AM',
              amount: '- ₱800.00',
              isNegative: true,
            ),
            const SizedBox(height: 16),

            // Date Group: Yesterday - Aug 22, 2026
            const Text(
              'Yesterday - Aug 22, 2026',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            _buildTransactionTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Wallet Top-up',
              subtitle: 'GCash\n03:20 PM',
              amount: '+ ₱2,000.00',
              isNegative: false,
            ),
            const SizedBox(height: 16),

            // Date Group: Aug 18, 2026
            const Text(
              'Aug 18, 2026',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            _buildTransactionTile(
              icon: Icons.medical_services_outlined,
              title: 'Dental X-Ray',
              subtitle: 'Payment\n11:05 AM',
              amount: '- ₱500.00',
              isNegative: true,
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildTransactionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String amount,
    required bool isNegative,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Text(
                amount,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isNegative ? AppColors.textPrimary : AppColors.success,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 16),
            ],
          ),
        ],
      ),
    );
  }
}