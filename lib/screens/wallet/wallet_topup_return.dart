import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/repositories/patient_api.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/repositories/wallet_topup_api.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';

/// The website's banner tones (js/wallet-topup-return.js).
enum TopupBannerKind { confirming, success, error, warning }

class TopupBanner {
  final TopupBannerKind kind;
  final String message;

  /// True while polling, so the banner shows a spinner.
  final bool busy;
  const TopupBanner(this.kind, this.message, {this.busy = false});

  /// Success green, error red, warning amber, confirming indigo.
  Color get color => switch (kind) {
        TopupBannerKind.success => const Color(0xFF16A34A),
        TopupBannerKind.error => const Color(0xFFDC2626),
        TopupBannerKind.warning => const Color(0xFFB45309),
        TopupBannerKind.confirming => const Color(0xFF4F46E5),
      };
}

/// Confirms a PayMongo checkout after the patient comes back from it.
///
/// A redirect back is not proof of payment, so nothing is shown as paid until
/// the server says so. The request id is kept on the device when the checkout
/// opens; when the screen is shown or the app resumes — even after the app was
/// closed mid-checkout — this polls `wallet_topup_requests` every 3 s, up to 30
/// times, and asks `reconcile-topup` to check PayMongo on tries 1, 4, 10 and
/// 20, in case the webhook is late. A dropped connection only costs a try.
///
/// What the money was for decides the message: a cash-in "added to your
/// wallet", a charge or a clinic request "paid" — never the other way round.
mixin WalletTopupReturn<T extends StatefulWidget> on State<T>, WidgetsBindingObserver {
  static const _maxTries = 30;
  static const _reconcileOn = {1, 4, 10, 20};

  /// Requests some screen is already confirming. The Wallet tab and a Cash
  /// In opened over a booking can both be alive; only one polls.
  static final Set<String> _active = {};

  TopupBanner? topupBanner;
  Timer? _pollTimer;
  String? _pollingId;

  /// Called once a payment is confirmed, after the record is reloaded.
  void onTopupSettled(TopupState state) {}

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    walletCheckReturn();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) walletCheckReturn();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    walletStopPoll();
    super.dispose();
  }

  void walletStopPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_pollingId != null) _active.remove(_pollingId);
    _pollingId = null;
  }

  Future<void> walletCheckReturn() async {
    final requestId = await WalletTopupApi.pendingRequestId();
    if (!mounted || requestId == null || requestId == _pollingId) return;
    if (_active.contains(requestId)) return;
    walletStopPoll();
    _pollingId = requestId;
    _active.add(requestId);
    setState(() => topupBanner =
        const TopupBanner(TopupBannerKind.confirming, 'Confirming your payment…', busy: true));
    _poll(requestId, 1);
  }

  Future<void> _poll(String requestId, int attempt) async {
    if (!mounted || _pollingId != requestId) return;
    if (_reconcileOn.contains(attempt)) await WalletTopupApi.reconcile(requestId);

    TopupState? state;
    var reached = true;
    try {
      state = await WalletTopupApi.fetchState(requestId);
    } catch (_) {
      reached = false;
    }
    if (!mounted || _pollingId != requestId) return;

    if (reached && state == null) {
      await _forget(requestId);
      _finish(TopupBannerKind.warning, 'That payment could not be found.');
      return;
    }

    switch (state?.status) {
      case 'paid':
        await _forget(requestId);
        await _settled(state!);
        return;
      case 'failed':
      case 'expired':
        await _forget(requestId);
        final reason = (state!.failureReason ?? '').trim();
        final base = state.status == 'expired'
            ? (state.purpose == 'wallet'
                ? 'That top-up timed out and was not charged.'
                : 'That payment timed out and was not charged.')
            : 'That payment did not go through.';
        _finish(TopupBannerKind.error, reason.isEmpty ? base : '$base — $reason');
        return;
    }

    if (attempt >= _maxTries) {
      // Still pending, or the connection kept failing. Kept on the device, so
      // the next resume checks again; nothing is shown as paid meanwhile.
      _finish(
        TopupBannerKind.warning,
        'Still waiting on the payment provider. If the money left your account it will '
        'appear here shortly — it is safe to leave this page.',
      );
      return;
    }
    _pollTimer = Timer(const Duration(seconds: 3), () => _poll(requestId, attempt + 1));
  }

  Future<void> _forget(String requestId) async {
    if (await WalletTopupApi.pendingRequestId() == requestId) await WalletTopupApi.savePending(null);
  }

  Future<void> _settled(TopupState state) async {
    final amount = formatPeso(state.amountCentavos / 100);
    switch (state.purpose) {
      case 'bill':
        final bill = state.billingRecordId == null
            ? null
            : await PatientApi.fetchCharge(state.billingRecordId!).catchError((_) => null);
        if (!mounted) return;
        if (bill != null && bill.isPaid) {
          _finish(TopupBannerKind.success, '$amount paid for ${bill.procedureName}.');
          showAppToast(context, 'Charge paid — your receipt is in Billing & Receipts.');
        } else {
          _finish(
            TopupBannerKind.warning,
            'Your $amount payment was received, but that charge was already settled. '
            'Please contact the clinic — you may be due a refund.',
          );
        }
      case 'visit':
        final request = state.visitRequestId == null
            ? null
            : await PatientApi.fetchVisitRequest(state.visitRequestId!).catchError((_) => null);
        if (!mounted) return;
        if (request != null && request.status == 'paid') {
          _finish(TopupBannerKind.success, '$amount paid to the clinic for your visit.');
          showAppToast(context, 'Paid — the clinic has been notified.');
        } else {
          _finish(
            TopupBannerKind.warning,
            'Your $amount payment was received, but that request was no longer open. '
            'Please contact the clinic — you may be due a refund.',
          );
        }
      case 'booking':
        _finish(
          TopupBannerKind.warning,
          'Your $amount downpayment was received. Please check Appointments, or contact '
          'the clinic to confirm your booking.',
        );
      default:
        _finish(TopupBannerKind.success, '$amount added to your wallet.');
        showAppToast(context, 'Top-up complete.');
    }
    await PatientRepository().load(force: true);
    if (mounted) onTopupSettled(state);
  }

  void _finish(TopupBannerKind kind, String message) {
    walletStopPoll();
    if (mounted) setState(() => topupBanner = TopupBanner(kind, message));
  }
}
