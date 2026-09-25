import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/services/session_controller.dart';
import 'package:mb_dental_app/services/supabase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// No session is ever established here, which is the state the app is in on a
/// clean install and after a sign-out.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  group('session checks', () {
    test('no stored session is not a login', () async {
      expect(SupabaseService.currentSession, isNull);
      expect(SupabaseService.isSignedIn, isFalse);
      expect(SupabaseService.hasValidSession, isFalse);
      expect(
        await SupabaseService.restoreSession(),
        SessionRestoreResult.signedOut,
      );
    });
  });

  group('sign-out cleanup', () {
    test('drops the session-scoped preference keys', () async {
      SharedPreferences.setMockInitialValues({
        'wallet_pending_topup': 'req-1',
        'theme_mode': 'dark',
      });

      await SessionController.clearLocalState();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('wallet_pending_topup'), isNull);
      // Device preferences are not the patient's data and survive a sign-out.
      expect(prefs.getString('theme_mode'), 'dark');
    });

    test('signing out with no session still completes', () async {
      await expectLater(SessionController.signOut(), completes);
      expect(SupabaseService.isSignedIn, isFalse);
    });
  });
}
