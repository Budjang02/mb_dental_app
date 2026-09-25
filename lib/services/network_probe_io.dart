import 'dart:async';
import 'dart:io';

/// Native clients can resolve the configured Supabase host before a request.
/// No alternate resolver or endpoint is ever used.
Future<bool> canReachServer(Uri serverUri, Duration timeout) async {
  try {
    final addresses = await InternetAddress.lookup(serverUri.host).timeout(timeout);
    return addresses.isNotEmpty;
  } on SocketException {
    return false;
  } on TimeoutException {
    return false;
  }
}
