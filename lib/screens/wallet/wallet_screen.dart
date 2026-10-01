import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/section_states.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cash_in_dialog.dart';
import 'pay_screens.dart';
import 'scan_to_pay_screen.dart';
import 'transaction_history_screen.dart';
import 'wallet_history.dart';
import 'wallet_topup_return.dart';

/// My Wallet, as on the website (js/patient-wallet.js): the clinic's pending
/// payment requests, the Available Balance card with Cash In and Pay Bill, and
/// the Transaction History.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with WidgetsBindingObserver, WalletTopupReturn {
  final PatientRepository _repository = PatientRepository();

  /// Remembered per device under the website's own key name, like dark mode:
  /// the flag hides nothing itself, only what it covers.
  static const _hiddenKey = 'mbWalletHidden';
  bool _balanceHidden = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance()
        .then((prefs) {
          if (mounted)
            setState(() => _balanceHidden = prefs.getBool(_hiddenKey) ?? false);
        })
        .catchError((_) {});
  }

  Future<void> _toggleHidden() async {
    setState(() => _balanceHidden = !_balanceHidden);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hiddenKey, _balanceHidden);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Wallet'),
        actions: [
          IconButton(
            tooltip: 'Transaction History & Billing',
            icon: Icon(CupertinoIcons.clock, color: AppColors.textPrimary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TransactionHistoryScreen(),
              ),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_repository, ThemeController()]),
        builder: (context, _) {
          return RefreshIndicator(
            onRefresh: () => _repository.load(force: true),
            edgeOffset: 12,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 104),
              children: [
                if (topupBanner != null) ...[
                  _banner(topupBanner!),
                  const SizedBox(height: 12),
                ],
                for (final request in _repository.visitRequests)
                  VisitRequestCard(request: request),
                _balanceCard(),
                const SizedBox(height: 24),
                const WalletHistoryCard(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _banner(TopupBanner banner) {
    final color = banner.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          if (banner.busy)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            FaIcon(
              switch (banner.kind) {
                TopupBannerKind.success => FontAwesomeIcons.circleCheck,
                TopupBannerKind.error => FontAwesomeIcons.circleXmark,
                _ => FontAwesomeIcons.triangleExclamation,
              },
              size: 16,
              color: color,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              banner.message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceCard() {
    final status = _repository.effectiveStatusOf(SyncSection.wallet);
    final known = _repository.isWalletBalanceKnown;

    ButtonStyle white() => ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF0C4A43),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      minimumSize: const Size(0, 44),
    );

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
                ? const [
                    Color(0xFF0C4A43),
                    Color(0xFF1B8C7C),
                    Color(0xFF0D5B52),
                  ]
                : const [
                    Color(0xFF12796D),
                    Color(0xFF23A793),
                    Color(0xFF158A7B),
                  ],
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
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, box) => ConstrainedBox(
                // Sized to its content: a compact card, no fixed card ratio.
                constraints: const BoxConstraints(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Available Balance',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Tooltip(
                                message: _balanceHidden
                                    ? 'Show balance'
                                    : 'Hide balance',
                                child: InkWell(
                                  onTap: _toggleHidden,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      _balanceHidden
                                          ? CupertinoIcons.eye_slash
                                          : CupertinoIcons.eye,
                                      color: Colors.white70,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Only a balance `wallet_balance()` confirmed is printed. A
                          // zero that means "we could not check" would be a lie about
                          // the patient's money.
                          Text(
                            !known
                                ? '₱ —'
                                : (_balanceHidden
                                      ? '₱ ••••••'
                                      : formatPeso(_repository.walletBalance)),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (!known) ...[
                            const SizedBox(height: 10),
                            if (status.hasFailed || !status.isPending)
                              SectionErrorLine(
                                status: status.hasFailed
                                    ? status
                                    : SectionStatus.failed(
                                        LoadFailure.server,
                                        'We could not check your balance.',
                                      ),
                                foreground: Colors.white70,
                                isRetrying: _repository.isRetrying(
                                  SyncSection.wallet,
                                ),
                                onRetry: () => _repository.retrySection(
                                  SyncSection.wallet,
                                ),
                              )
                            else
                              const Text(
                                'Checking your balance…',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                ),
                              ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: white(),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CashInScreen(),
                                ),
                              ),
                              icon: const Icon(TablerIcons.plus, size: 18),
                              label: const Text(
                                'Cash In',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Same white fill as Cash In: two equal actions on the card.
                          Expanded(
                            child: ElevatedButton.icon(
                              style: white(),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ScanToPayScreen(),
                                ),
                              ),
                              icon: const Icon(TablerIcons.scan, size: 18),
                              label: const Text(
                                'Pay using QR',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
