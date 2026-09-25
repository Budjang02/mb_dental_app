import 'dart:async';

import 'package:http/http.dart' as http;

import 'network_probe_stub.dart'
    if (dart.library.html) 'network_probe_web.dart'
    if (dart.library.io) 'network_probe_io.dart' as network_probe;

/// A safe, patient-facing description for all transport failures.
const String kServerConnectionMessage =
    'Unable to connect to the server. Please check your internet connection and try again.';

/// Thrown before a Supabase request when the device cannot resolve the
/// configured Supabase host. It contains no endpoint or credential data, so it
/// is safe to translate at the presentation boundary.
class NetworkUnavailableException implements Exception {
  const NetworkUnavailableException();

  @override
  String toString() => 'Network connection unavailable';
}

/// Checks DNS resolution of this app's configured Supabase host. A Wi-Fi icon
/// is not proof that it can reach the internet: captive portals and
/// DNS-blocking hotspots are common, so the configured server must resolve
/// before a request is started.
class NetworkService {
  NetworkService._();

  static const Duration _probeTimeout = Duration(seconds: 5);
  static const Duration _successCacheLifetime = Duration(seconds: 8);

  static Uri? _serverUri;
  static DateTime? _lastSuccessfulProbe;

  static bool get isConfigured => _serverUri != null;

  /// Called while Supabase is initialized. The host is read from `.env`; no
  /// fallback endpoint, DNS server, key, or credential is introduced here.
  static void configure(Uri serverUri) {
    _serverUri = serverUri;
    _lastSuccessfulProbe = null;
  }

  static void invalidateReachabilityCache() {
    _lastSuccessfulProbe = null;
  }

  /// Whether a connection is available and the configured Supabase hostname
  /// currently resolves. Successful probes are briefly cached so a dashboard
  /// load does not perform one DNS lookup per parallel request.
  static Future<bool> canReachServer({bool force = false}) async {
    final serverUri = _serverUri;
    if (serverUri == null || serverUri.host.isEmpty) return false;

    final lastSuccess = _lastSuccessfulProbe;
    if (!force &&
        lastSuccess != null &&
        DateTime.now().difference(lastSuccess) < _successCacheLifetime) {
      return true;
    }

    try {
      if (!await network_probe.canReachServer(serverUri, _probeTimeout)) {
        return false;
      }
      _lastSuccessfulProbe = DateTime.now();
      return true;
    } catch (_) {
      // A platform connectivity failure is still not a reason to expose a
      // transport exception or an endpoint to a patient.
      return false;
    }
  }

  /// Fails early with a stable, non-technical error that the UI can retry.
  static Future<void> requireServerConnection() async {
    if (!await canReachServer()) throw const NetworkUnavailableException();
  }

  /// Identifies errors caused by a missing connection, DNS failure, transport
  /// exception, or timeout. The app deliberately does not show their raw text.
  static bool isConnectionFailure(Object error) {
    if (error is NetworkUnavailableException ||
        error is TimeoutException ||
        error is http.ClientException) {
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
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await NetworkService.requireServerConnection();
    try {
      return await _delegate.send(request).timeout(_requestTimeout);
    } catch (error) {
      if (NetworkService.isConnectionFailure(error)) {
        NetworkService.invalidateReachabilityCache();
      }
      rethrow;
    }
  }

  @override
  void close() => _delegate.close();
}
