import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Single entry point for the Supabase backend.
///
/// Credentials come from the bundled `.env` (see `.env.example`), which holds
/// the anon/publishable key only. Every table this app touches is protected by
/// row-level security, so the key on its own grants nothing beyond the public
/// reference data (clinic details and the procedure catalog) — patient rows
/// only become visible once a patient signs in.
class SupabaseService {
  SupabaseService._();

  /// Reads `.env` and opens the connection. Must finish before `runApp`,
  /// because [client] and the auth screens assume an initialized instance.
  static Future<void> initialize() async {
    await dotenv.load(fileName: '.env');

    final url = dotenv.env['VITE_SUPABASE_URL'];
    final anonKey = dotenv.env['VITE_SUPABASE_ANON_KEY'];

    if (url == null || url.isEmpty || anonKey == null || anonKey.isEmpty) {
      throw StateError(
        'Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY in .env. '
        'Copy .env.example to .env and fill it in.',
      );
    }

    await Supabase.initialize(url: url, publishableKey: anonKey);
  }

  static SupabaseClient get client => Supabase.instance.client;

  static GoTrueClient get auth => client.auth;

  /// The signed-in patient's auth id, or null when nobody is signed in.
  /// This is the value RLS policies compare against, so it is also the key
  /// every patient-scoped query filters on.
  static String? get currentUserId => auth.currentUser?.id;

  static bool get isSignedIn => auth.currentUser != null;

  /// Emits on sign-in, sign-out, and token refresh. The splash screen listens
  /// to decide between the login screen and the dashboard.
  static Stream<AuthState> get onAuthStateChange => auth.onAuthStateChange;
}
