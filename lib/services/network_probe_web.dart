import 'dart:async';
import 'dart:html' as html;

/// Browsers deliberately do not allow a page to perform an arbitrary DNS
/// lookup. `navigator.onLine` is the only safe pre-flight signal; the actual
/// Supabase request is still guarded by a timeout and catches browser fetch
/// errors such as DNS failure, captive portals and blocked egress.
Future<bool> canReachServer(Uri serverUri, Duration timeout) async =>
    html.window.navigator.onLine;
