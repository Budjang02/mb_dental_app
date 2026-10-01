import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/payment.dart';
import 'package:mb_dental_app/repositories/patient_api.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/repositories/wallet_topup_api.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
import 'package:mb_dental_app/widgets/wallet_txn_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Pay Bill and Pay the Clinic — js/patient-wallet.js (openWalletPayModal)
// and js/patient-visit-pay.js. Both settle in full: the wallet through its
// own database function, GCash / GrabPay through a PayMongo checkout that the
// server prices. Nothing here ever marks anything paid by itself.

const String _walletRail = 'wallet';

String _date(String raw) {
  final d = DateTime.tryParse(raw);
  if (d == null) return '—';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

String _billDate(DateTime d) {
  final m = manilaTime(d);
  return _date('${m.year}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}');
}

/// A server refusal in words the patient can act on.
String _payError(Object e) {
  final message = e is PostgrestException ? e.message : (e is CashInException ? e.message : '');
  final lower = message.toLowerCase();
  if (lower.contains('insufficient') || lower.contains('not enough')) {
    return 'Not enough balance. Cash In first, or pay with GCash or GrabPay.';
  }
  if (lower.contains('already paid') || lower.contains('already settled')) {
    return 'That has already been paid.';
  }
  if (lower.contains('void') || lower.contains('cancel')) return 'That charge is no longer payable.';
  if (lower.contains('jwt') || lower.contains('session')) return 'Your session has ended. Please sign in again.';
  if (e is PostgrestException && RegExp('schema cache|does not exist|function', caseSensitive: false).hasMatch(message)) {
    return "The wallet is not set up on this clinic's database yet.";
  }
  if (message.isNotEmpty) return message;
  return 'Could not complete the payment. Please try again.';
}

/// Opens Pay Bill, or says there is nothing to pay.
Future<void> openPayBill(BuildContext context) async {
  final charges = PatientRepository().unpaidCharges;
  if (charges.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            FaIcon(FontAwesomeIcons.circleCheck, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Flexible(child: Text('Nothing to pay', style: TextStyle(color: AppColors.textPrimary))),
          ],
        ),
        content: Text('You have no outstanding charges right now.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Close'))],
      ),
    );
    return;
  }
  await Navigator.push(context, MaterialPageRoute(builder: (_) => const PayBillScreen()));
}

/// Opens a clinic payment request by id — from a notice, a QR code or a link.
/// It only shows the request; paying still takes a tap on Pay.
Future<void> openVisitRequest(BuildContext context, String requestId) {
  return Navigator.push(context, MaterialPageRoute(builder: (_) => VisitPayScreen(requestId: requestId)));
}

/// Wallet balance, GCash and GrabPay, one selected, with a check on it.
class PayRailPicker extends StatelessWidget {
  final String selected;
  final double balance;
  final bool balanceKnown;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const PayRailPicker({
    super.key,
    required this.selected,
    required this.balance,
    required this.balanceKnown,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget row(String id, Widget logo, String label, [String? note]) {
      final on = selected == id;
      return Semantics(
        inMutuallyExclusiveGroup: true,
        checked: on,
        label: label,
        child: InkWell(
          onTap: enabled ? () => onChanged(id) : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: on ? AppColors.primary.withValues(alpha: 0.06) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on ? AppColors.primary : AppColors.border),
            ),
            child: Row(
              children: [
                SizedBox(width: 44, child: Center(child: logo)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: label,
                      children: [
                        if (note != null)
                          TextSpan(
                            text: '  $note',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ),
                SizedBox(
                  width: 22,
                  child: on ? WalletGlyphIcon(WalletGlyph.check, size: 20, color: AppColors.primary) : null,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        row(_walletRail, WalletGlyphIcon(WalletGlyph.wallet, size: 22, color: AppColors.primary), 'Wallet balance',
            balanceKnown ? formatPeso(balance) : 'unavailable'),
        for (final rail in kCashInRails) ...[
          const SizedBox(height: 8),
          row(rail.id, SvgPicture.asset(rail.logo, height: 16), rail.label),
        ],
      ],
    );
  }
}

/// The primary "Pay Now" button with a lock, or a spinner while it works.
class _PayButton extends StatelessWidget {
  final bool busy;
  final String busyLabel;
  final VoidCallback onPressed;

  const _PayButton({required this.busy, required this.busyLabel, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0D9488),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: busy
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  const SizedBox(width: 10),
                  Text(busyLabel),
                ],
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FaIcon(FontAwesomeIcons.lock, size: 14, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Pay Now', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }
}

Widget _errorLine(String? error) => error == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(error, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
      );

Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
    );

Future<bool> _openCheckout(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

// --- Pay Bill ---

class PayBillScreen extends StatefulWidget {
  const PayBillScreen({super.key});

  @override
  State<PayBillScreen> createState() => _PayBillScreenState();
}

class _PayBillScreenState extends State<PayBillScreen> {
  final _repository = PatientRepository();
  String? _billId;
  late String _rail;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final charges = _repository.unpaidCharges;
    final first = charges.isEmpty ? null : charges.first;
    _billId = first?.id;
    // Offered first because it finishes without leaving the app; selected
    // only when it covers the charge selected beside it.
    final covers = _repository.isWalletBalanceKnown && first != null && _repository.walletBalance >= first.amount;
    _rail = covers ? _walletRail : kCashInRails.first.id;
  }

  Future<void> _submit() async {
    final billId = _billId;
    if (billId == null) {
      setState(() => _error = 'Pick a charge to pay.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Read again right before paying: settled, voided or unaffordable since
      // the list was drawn is caught here rather than by a failed payment.
      final charge = await PatientApi.fetchCharge(billId);
      if (charge == null || charge.isVoided) throw const _Refusal('That charge is no longer payable.');
      if (charge.isPaid) throw const _Refusal('That charge has already been paid.');

      if (_rail == _walletRail) {
        final balance = await PatientApi.fetchWalletBalance();
        if (charge.amount > balance) throw const _Refusal('Not enough balance for that charge. Add money first.');
        await PatientApi.payBillWithWallet(billId);
        if (!mounted) return;
        showAppToast(context, 'Payment complete — your receipt is in Billing & Receipts.');
        await _repository.load(force: true);
        if (mounted) Navigator.pop(context, true);
        return;
      }

      final url = await WalletTopupApi.createCheckout(billId: billId, paymentMethod: _rail);
      if (!await _openCheckout(url)) throw const _Refusal('The checkout page could not be opened.');
      // The Wallet confirms it when the patient comes back.
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is _Refusal ? e.message : _payError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_repository, ThemeController()]),
      builder: (context, _) {
        final charges = _repository.unpaidCharges;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: const Text('Pay a Charge')),
          bottomNavigationBar: _PayButton(busy: _busy, busyLabel: _rail == _walletRail ? 'Paying…' : 'Opening…', onPressed: _submit),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Text('A charge is paid in full, so pick one at a time.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              _errorLine(_error),
              for (final b in charges) ...[
                _ChargeTile(
                  charge: b,
                  selected: b.id == _billId,
                  onTap: _busy ? null : () => setState(() => _billId = b.id),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 10),
              _label('Pay with'),
              PayRailPicker(
                selected: _rail,
                balance: _repository.walletBalance,
                balanceKnown: _repository.isWalletBalanceKnown,
                enabled: !_busy,
                onChanged: (r) => setState(() => _rail = r),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChargeTile extends StatelessWidget {
  final Payment charge;
  final bool selected;
  final VoidCallback? onTap;

  const _ChargeTile({required this.charge, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.06) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(charge.procedureName,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('Billed ${_billDate(charge.billedOn)}',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Text(formatPeso(charge.amount),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _Refusal implements Exception {
  final String message;
  const _Refusal(this.message);
}

// --- Payment requests from the clinic ---

/// The card above the balance: a pending bill the clinic sent.
class VisitRequestCard extends StatelessWidget {
  final VisitPaymentRequest request;

  const VisitRequestCard({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0D9488);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: teal.withValues(alpha: ThemeController().isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: teal),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: teal, borderRadius: BorderRadius.circular(10)),
            child: const FaIcon(FontAwesomeIcons.fileInvoiceDollar, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payment request from the clinic',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  request.visitDate.isEmpty ? 'For your visit' : 'For your visit on ${_date(request.visitDate)}',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(formatPeso(request.amount),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => openVisitRequest(context, request.id),
            style: ElevatedButton.styleFrom(
              backgroundColor: teal,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const FaIcon(FontAwesomeIcons.lock, size: 12, color: Colors.white),
            label: const Text('Pay'),
          ),
        ],
      ),
    );
  }
}

/// "Pay the Clinic" for one request: the amount, the itemised bill the clinic
/// sent, and how to pay. The request is read fresh, so one already paid or
/// withdrawn says so instead of offering to pay it.
class VisitPayScreen extends StatefulWidget {
  final String requestId;

  const VisitPayScreen({super.key, required this.requestId});

  @override
  State<VisitPayScreen> createState() => _VisitPayScreenState();
}

class _VisitPayScreenState extends State<VisitPayScreen> {
  final _repository = PatientRepository();
  VisitPaymentRequest? _request;
  bool _loading = true;
  String? _loadError;
  String _rail = _walletRail;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final request = await PatientApi.fetchVisitRequest(widget.requestId);
      if (!mounted) return;
      final covers = _repository.isWalletBalanceKnown && request != null && _repository.walletBalance >= request.amount;
      setState(() {
        _request = request;
        _rail = covers ? _walletRail : kCashInRails.first.id;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not open that payment request. Check your connection and try again.';
      });
    }
  }

  Future<void> _submit() async {
    final request = _request;
    if (request == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fresh = await PatientApi.fetchVisitRequest(request.id);
      if (fresh == null || !fresh.isPending) {
        if (mounted) {
          setState(() {
            _request = fresh;
            _busy = false;
          });
        }
        return;
      }
      if (_rail == _walletRail) {
        final balance = await PatientApi.fetchWalletBalance();
        if (fresh.amount > balance) {
          throw const _Refusal('Not enough balance. Cash In first, or pay with GCash or GrabPay.');
        }
        await PatientApi.payVisitRequestWithWallet(fresh.id);
        if (!mounted) return;
        showAppToast(context, 'Paid ${formatPeso(fresh.amount)} — the clinic has been notified.');
        await _repository.load(force: true);
        if (mounted) Navigator.pop(context, true);
        return;
      }
      final url = await WalletTopupApi.createCheckout(visitRequestId: fresh.id, paymentMethod: _rail);
      if (!await _openCheckout(url)) throw const _Refusal('The checkout page could not be opened.');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is _Refusal ? e.message : _payError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    final payable = request != null && request.isPending;
    return ListenableBuilder(
      listenable: Listenable.merge([_repository, ThemeController()]),
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Pay the Clinic')),
        bottomNavigationBar: payable
            ? _PayButton(busy: _busy, busyLabel: _rail == _walletRail ? 'Paying…' : 'Opening…', onPressed: _submit)
            : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? _Message(text: _loadError!, action: TextButton(onPressed: _load, child: const Text('Try again')))
                : !payable
                    ? _Message(
                        text: request == null
                            ? 'That payment request is no longer available.'
                            : request.status == 'cancelled'
                                ? 'The clinic withdrew that payment request.'
                                : 'That payment request has already been paid.',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        children: [
                          Row(
                            children: [
                              FaIcon(FontAwesomeIcons.fileInvoiceDollar, size: 18, color: AppColors.primary),
                              const SizedBox(width: 10),
                              Text(
                                request.visitDate.isEmpty ? 'For your visit' : 'For your visit on ${_date(request.visitDate)}',
                                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(formatPeso(request.amount),
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          const SizedBox(height: 14),
                          if (request.breakdown != null) _Breakdown(request.breakdown!),
                          const SizedBox(height: 14),
                          _errorLine(_error),
                          _label('Pay with'),
                          PayRailPicker(
                            selected: _rail,
                            balance: _repository.walletBalance,
                            balanceKnown: _repository.isWalletBalanceKnown,
                            enabled: !_busy,
                            onChanged: (r) => setState(() => _rail = r),
                          ),
                        ],
                      ),
      ),
    );
  }
}

/// The itemised bill (`_vpBreakdownHtml`): services, medication, totals, the
/// down payment applied and the balance being paid.
class _Breakdown extends StatelessWidget {
  final Map<String, dynamic> b;

  const _Breakdown(this.b);

  double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    Widget line(String label, String amount, {bool strong = false, bool indent = false, Color? color}) => Padding(
          padding: EdgeInsets.fromLTRB(indent ? 10 : 0, 4, 0, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                        color: indent ? AppColors.textSecondary : AppColors.textPrimary)),
              ),
              Text(amount,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                      color: color ?? AppColors.textPrimary)),
            ],
          ),
        );
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(text,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        );
    List<Map> items(Object? v) => v is List ? v.whereType<Map>().toList() : const [];
    final services = items(b['services']);
    final meds = items(b['medications']);
    final down = _n(b['down_payment']);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('Dental services'),
          for (final s in services) line('${s['name'] ?? 'Service'}', formatPeso(_n(s['amount'])), indent: true),
          if (meds.isNotEmpty) ...[
            heading('Medication'),
            for (final m in meds)
              line('${m['name'] ?? 'Medicine'}${m['qty'] != null ? ' × ${m['qty']}' : ''}', formatPeso(_n(m['amount'])),
                  indent: true),
          ],
          Divider(color: AppColors.border),
          line('Dental services total', formatPeso(_n(b['services_total']))),
          line('Medication total', formatPeso(_n(b['medication_total']))),
          line('Subtotal', formatPeso(_n(b['subtotal'])), strong: true),
          if (down > 0) line('Down payment applied', '−${formatPeso(down)}', color: const Color(0xFF16A34A)),
          line('Remaining balance due', formatPeso(_n(b['balance'])), strong: true),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final Widget? action;

  const _Message({required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(FontAwesomeIcons.fileInvoiceDollar, size: 30, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
