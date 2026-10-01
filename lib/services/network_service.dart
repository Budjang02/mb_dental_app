import 'dart:async';

import 'package:http/http.dart' as http;

/// A safe, patient-facing description for all transport failures.
const String kServerConnectionMessage =
    'Unable to connect to the server. Please check your internet connection and try again.';

/// Converts real transport failures into a single safe, retryable state.
///
/// Do not use a DNS or connectivity pre-flight to decide whether to start a
/// request. Some valid networks have slow, filtered, or split DNS, and the
/// actual HTTPS request is the only reliable test of whether Supabase is
/// reachable from the device.
class NetworkService {
  NetworkService._();

  /// Identifies errors caused by a missing connection, DNS failure, transport
  /// exception, or timeout. The app deliberately does not show their raw text.
  static bool isConnectionFailure(Object error) {
    if (error is TimeoutException || error is http.ClientException) {
      return true;
    }

    final text = error.toString().toLowerCase();
    return text.contains('failed host lookup') ||
        text.contains('socketexception') ||
        text.contains('clientexception') ||
        text.contains('failed to fetch') ||
        text.contains('err_name_not_resolved') ||
        text.contains('name not resolved') ||
        text.contains('dns') ||
        text.contains('network error') ||
        text.contains('connection closed') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('network is unreachable') ||
        text.contains('network connection unavailable') ||
        text.contains('timed out') ||
        text.contains('timeout');
  }
}

/// Wraps every HTTP request Supabase makes, including Auth, PostgREST,
/// Functions and Storage. Realtime uses its own socket transport and simply
/// reconnects when connectivity returns.
class ConnectivityAwareClient extends http.BaseClient {
  static const Duration _requestTimeout = Duration(seconds: 20);

  final http.Client _delegate;

  ConnectivityAwareClient([http.Client? delegate]) : _delegate = delegate ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _delegate.send(request).timeout(_requestTimeout);

  @override
  void close() => _delegate.close();
}
