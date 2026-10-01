import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/repositories/wallet_topup_api.dart';
import 'package:mb_dental_app/widgets/wallet_txn_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'wallet_topup_return.dart';

/// Kept as a compatibility helper for any older callers. Cash In is now a
/// route, never a pop-up.
Future<bool> showCashInDialog(BuildContext context) async {
  return (await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CashInScreen()))) ?? false;
}

class CashInScreen extends StatefulWidget {
  /// Prefilled amount in pesos, e.g. the shortfall a booking needs.
  final double? initialAmount;

  /// Opened from a booking: after checkout this screen stays open, confirms
  /// the payment when the patient comes back, and then returns to the booking
  /// (popping `true`) instead of leaving them on the Wallet.
  final bool returnToCaller;

  const CashInScreen({super.key, this.initialAmount, this.returnToCaller = false});

  @override
  State<CashInScreen> createState() => _CashInScreenState();
}

class _CashInScreenState extends State<CashInScreen> with WidgetsBindingObserver, WalletTopupReturn {
  static const _quickAmounts = <(int, String)>[(500, '₱500'), (1000, '₱1,000'), (2000, '₱2,000'), (5000, '₱5,000')];

  // Owned by this State so it is disposed only after the window's closing
  // animation, never while the field is still on screen.
  final TextEditingController _amount = TextEditingController();
  String? _rail = kCashInRails.first.id;
  String? _error;
  bool _busy = false;

  /// True once a checkout from a booking is open, so this screen — not the
  /// Wallet — confirms it.
  bool _awaiting = false;

  @override
  void initState() {
    super.initState();
    final amount = widget.initialAmount;
    if (amount != null && amount > 0) _amount.text = amount.toStringAsFixed(2);
  }

  @override
  Future<void> walletCheckReturn() async {
    if (_awaiting) await super.walletCheckReturn();
  }

  @override
  void onTopupSettled(TopupState state) {
    if (widget.returnToCaller && state.status == 'paid' && state.purpose == 'wallet') {
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  String? _validate(double? pesos) {
    if (pesos == null || pesos <= 0) return 'Enter an amount greater than zero.';
    final centavos = (pesos * 100).round();
    if (centavos < WalletTopupApi.minCentavos) return 'The smallest top-up is ₱20.00.';
    if (centavos > WalletTopupApi.maxCentavos) return 'The most you can add at once is ₱100,000.00.';
    if (_rail == null) return 'Choose how you want to pay.';
    return null;
  }

  Future<void> _confirm() async {
    final pesos = double.tryParse(_amount.text.replaceAll(',', '').trim());
    final problem = _validate(pesos);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await WalletTopupApi.createCheckout(amountCentavos: (pesos! * 100).round(), paymentMethod: _rail!);
      final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!launched) {
        setState(() {
          _busy = false;
          _error = 'The checkout page could not be opened.';
        });
        return;
      }
      if (widget.returnToCaller) {
        // Stay: the booking is waiting on this money.
        setState(() {
          _busy = false;
          _awaiting = true;
          topupBanner = const TopupBanner(TopupBannerKind.confirming, 'Waiting for your payment…', busy: true);
        });
        return;
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is CashInException ? e.message : 'The checkout could not be opened. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Cash In')),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: ElevatedButton(
          onPressed: _busy ? null : _confirm,
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          child: _busy
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Opening...'),
                  ],
                )
              : const Text('Confirm'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (topupBanner != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: topupBanner!.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  if (topupBanner!.busy) ...[
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: topupBanner!.color),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(topupBanner!.message,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: topupBanner!.color)),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(fontSize: 13, color: Color(0xFFDC2626))),
          ],
          const SizedBox(height: 18),
          Text('Amount', style: label),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
            style: TextStyle(color: AppColors.textPrimary),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              isDense: true,
              hintText: '0.00',
              hintStyle: TextStyle(color: AppColors.textSecondary),
              fillColor: AppColors.background,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, text) in _quickAmounts)
                ActionChip(
                  label: Text(text),
                  labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  backgroundColor: AppColors.surface,
                  side: BorderSide(color: AppColors.border),
                  shape: const StadiumBorder(),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _amount.text = value.toString();
                          _error = null;
                        }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('₱20.00 – ₱100,000.00', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 18),
          Text('Pay with', style: label),
          const SizedBox(height: 8),
          _railList(),
          const SizedBox(height: 18),
          Visibility(
            visible: false,
            child: ElevatedButton(
            onPressed: _busy ? null : _confirm,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            child: _busy
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('Opening…'),
                    ],
                  )
                : const Text('Confirm'),
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }

  /// Bordered list, one row per rail: logo, name, and a check on the chosen one.
  Widget _railList() {
    final dark = ThemeController().isDark;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.transparent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(
          children: [
            for (var i = 0; i < kCashInRails.length; i++) ...[
              if (i > 0) const SizedBox(height: 1),
              _railRow(kCashInRails[i], dark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _railRow(CashInRail rail, bool dark) {
    final selected = _rail == rail.id;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: rail.label,
      child: Material(
        color: selected && !dark ? AppColors.primary.withOpacity(0.06) : Colors.transparent,
        child: InkWell(
          onTap: _busy ? null : () => setState(() => _rail = rail.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                SvgPicture.asset(rail.logo, height: 14),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    rail.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: dark ? const Color(0xFFE2E8F0) : AppColors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: selected ? WalletGlyphIcon(WalletGlyph.check, size: 20, color: AppColors.primary) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
