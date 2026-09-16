import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/repositories/wallet_topup_api.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';

enum TopupBannerKind { pending, paid, failed }

class TopupBanner {
  final TopupBannerKind kind;
  final String message;

  /// True while polling, so the banner shows a spinner.
  final bool busy;
  const TopupBanner(this.kind, this.message, {this.busy = false});
}

/// Confirms a PayMongo cash-in after the patient comes back from checkout.
///
/// The request id is kept on the device when the checkout opens. When the
/// wallet is shown or the app resumes, this polls `wallet_topup_requests`
/// every 3 s, up to 30 times, and asks `reconcile-topup` to check PayMongo on
/// tries 1, 4, 10 and 20. It never credits anything itself.
mixin WalletTopupReturn<T extends StatefulWidget> on State<T>, WidgetsBindingObserver {
  static const _maxTries = 30;
  static const _reconcileOn = {1, 4, 10, 20};

  TopupBanner? topupBanner;
  Timer? _pollTimer;
  String? _pollingId;

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
    _pollingId = null;
  }

  Future<void> walletCheckReturn() async {
    final requestId = await WalletTopupApi.pendingRequestId();
    if (!mounted || requestId == null || requestId == _pollingId) return;
    // Taken off the device now, as the website takes `?topup=` off the URL.
    await WalletTopupApi.savePending(null);
    if (!mounted) return;

    walletStopPoll();
    _pollingId = requestId;
    setState(() => topupBanner = const TopupBanner(TopupBannerKind.pending, 'Confirming your payment…', busy: true));
    _poll(requestId, 1);
  }

  Future<void> _poll(String requestId, int attempt) async {
    if (!mounted || _pollingId != requestId) return;
    if (_reconcileOn.contains(attempt)) await WalletTopupApi.reconcile(requestId);

    TopupState? state;
    try {
      state = await WalletTopupApi.fetchState(requestId);
    } catch (_) {
      state = null;
    }
    if (!mounted || _pollingId != requestId) return;

    switch (state?.status) {
      case 'paid':
        _finish(TopupBannerKind.paid, '${formatPeso(state!.amountCentavos / 100)} added to your wallet.');
        showAppToast(context, 'Top-up complete.');
        await PatientRepository().load(force: true);
        return;
      case 'failed':
        final reason = state!.failureReason;
        _finish(
          TopupBannerKind.failed,
          'That payment did not go through.${reason == null || reason.isEmpty ? '' : ' $reason'}',
        );
        return;
      case 'expired':
        _finish(TopupBannerKind.failed, 'That top-up timed out and was not charged.');
        return;
    }

    if (attempt >= _maxTries) {
      _finish(
        TopupBannerKind.pending,
        'Still waiting on the payment provider. If the money left your account it will '
        'appear here shortly — it is safe to leave this page.',
      );
      return;
    }
    _pollTimer = Timer(const Duration(seconds: 3), () => _poll(requestId, attempt + 1));
  }

  void _finish(TopupBannerKind kind, String message) {
    walletStopPoll();
    setState(() => topupBanner = TopupBanner(kind, message));
  }
}
