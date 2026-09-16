import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/// A PayMongo rail the patient can cash in with. [id] is the value the
/// `create-topup-source` function expects; [logo] is the bundled brand asset.
class CashInRail {
  final String id;
  final String label;
  final String logo;

  const CashInRail(this.id, this.label, this.logo);
}

const List<CashInRail> kCashInRails = [
  CashInRail('gcash', 'GCash', 'assets/wallet/gcash-mark.svg'),
  CashInRail('grab_pay', 'GrabPay', 'assets/wallet/grab-logo.svg'),
];

/// Where a top-up request stands on the server.
class TopupState {
  final String status;
  final int amountCentavos;
  final String? failureReason;

  const TopupState({required this.status, required this.amountCentavos, this.failureReason});
}

/// Raised when the checkout could not be opened. [message] is safe to show.
class CashInException implements Exception {
  final String message;
  const CashInException(this.message);

  @override
  String toString() => message;
}

/// PayMongo cash-in. The app never credits the wallet: it asks the server for
/// a checkout link, and only the `paymongo-webhook` function credits the
/// ledger once PayMongo confirms the payment.
class WalletTopupApi {
  WalletTopupApi._();

  static const int minCentavos = 2000;
  static const int maxCentavos = 10000000;

  /// Remembers the request being paid, so returning to the app — even after
  /// it was closed — still confirms the payment.
  static const String _pendingKey = 'wallet_pending_topup';

  /// Creates the top-up request and PaymentIntent. Returns the checkout URL.
  static Future<String> createCheckout({required int amountCentavos, required String paymentMethod}) async {
    final Map<String, dynamic> payload;
    try {
      // A patient may have left the app open long enough for its JWT to
      // expire. Refresh immediately before the protected checkout request.
      final refreshed = await SupabaseService.auth.refreshSession();
      final session = refreshed.session ?? SupabaseService.auth.currentSession;
      if (session == null) {
        throw const CashInException('Your session has ended. Please sign in again.');
      }
      final res = await SupabaseService.client.functions.invoke(
        'create-topup-source',
        body: {'amount_centavos': amountCentavos, 'payment_method': paymentMethod},
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      payload = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const {};
    } on AuthException {
      throw const CashInException('Your session has ended. Please sign in again.');
    } on FunctionException catch (e) {
      final details = e.details;
      final error = details is Map ? details['error'] : null;
      throw CashInException(
        error is String && error.isNotEmpty ? error : 'The checkout could not be opened. Please try again.',
      );
    }

    final url = payload['checkout_url'];
    if (url is! String || url.isEmpty) {
      throw const CashInException('No checkout link was returned.');
    }

    final requestId = payload['request_id'] ?? payload['topup_id'] ?? payload['id'];
    await savePending(requestId is String && requestId.isNotEmpty ? requestId : await _latestPendingId());
    return url;
  }

  static Future<String?> _latestPendingId() async {
    try {
      final rows = await SupabaseService.client
          .from('wallet_topup_requests')
          .select('id')
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(1);
      return rows.isEmpty ? null : rows.first['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> savePending(String? requestId) async {
    final prefs = await SharedPreferences.getInstance();
    if (requestId == null) {
      await prefs.remove(_pendingKey);
    } else {
      await prefs.setString(_pendingKey, requestId);
    }
  }

  static Future<String?> pendingRequestId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingKey);
  }

  static Future<TopupState?> fetchState(String requestId) async {
    final row = await SupabaseService.client
        .from('wallet_topup_requests')
        .select('status, amount_centavos, failure_reason')
        .eq('id', requestId)
        .maybeSingle();
    if (row == null) return null;
    return TopupState(
      status: (row['status'] as String?) ?? 'pending',
      amountCentavos: (row['amount_centavos'] as num?)?.toInt() ?? 0,
      failureReason: row['failure_reason'] as String?,
    );
  }

  /// Asks the server to check PayMongo directly, in case the webhook is late.
  static Future<void> reconcile(String requestId) async {
    try {
      await SupabaseService.client.functions.invoke('reconcile-topup', body: {'request_id': requestId});
    } catch (_) {
      // Best effort; polling carries on either way.
    }
  }
}
