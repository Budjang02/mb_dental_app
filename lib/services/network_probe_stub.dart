import 'dart:async';

/// Conservative fallback for platforms that expose neither browser online
/// state nor a socket DNS lookup. The actual request remains protected by the
/// timeout and error translation in `ConnectivityAwareClient`.
Future<bool> canReachServer(Uri serverUri, Duration timeout) async => true;
