import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/app/routes.dart';
import 'package:mb_dental_app/screens/auth/login_screen.dart';
import 'package:mb_dental_app/screens/auth/register_screen.dart';
import 'package:mb_dental_app/screens/dashboard/dashboard_screen.dart';
import 'package:mb_dental_app/screens/records/dental_records_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// No session is ever established here, so every protected route is being
/// asked for by a signed-out caller — which is the case the guard exists for.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  Widget? screenOf(String route) {
    final built = AppRoutes.onGenerateRoute(RouteSettings(name: route));
    if (built is! MaterialPageRoute) return null;
    return built.builder(_FakeContext());
  }

  group('route guard', () {
    test('sends a signed-out caller to Login instead of a patient screen', () {
      for (final route in AppRoutes.protected) {
        expect(screenOf(route), isA<LoginScreen>(), reason: route);
        expect(
          AppRoutes.onGenerateRoute(RouteSettings(name: route))!.settings.name,
          AppRoutes.login,
          reason: '$route should land on the Login route, not stack a second one',
        );
      }
    });

    test('leaves the auth routes themselves alone', () {
      expect(screenOf(AppRoutes.login), isA<LoginScreen>());
      expect(screenOf(AppRoutes.register), isA<RegisterScreen>());
    });

    test('guards every patient screen the app can name', () {
      final unguarded = AppRoutes.routes.keys
          .where((route) => route != AppRoutes.login && route != AppRoutes.register)
          .where((route) => !AppRoutes.protected.contains(route));
      expect(unguarded, isEmpty, reason: 'these routes show patient data unguarded');
    });

    test('an unknown route is not invented', () {
      expect(AppRoutes.onGenerateRoute(const RouteSettings(name: '/nope')), isNull);
    });

    testWidgets('a signed-out app opening on Records shows Login instead', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        initialRoute: AppRoutes.records,
        onGenerateRoute: AppRoutes.onGenerateRoute,
      ));
      await tester.pump();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(DentalRecordsScreen), findsNothing);
    });

    testWidgets('a push to a protected route while signed out lands on Login', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        initialRoute: AppRoutes.login,
        onGenerateRoute: AppRoutes.onGenerateRoute,
      ));
      await tester.pump();

      navigator.currentState!.pushNamed(AppRoutes.dashboard);
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
    });
  });
}

/// The builders under test only construct a widget; none of them reads the
/// context, so a stand-in is enough to call them outside a running app.
class _FakeContext extends StatelessElement {
  _FakeContext() : super(const _Nothing());
}

class _Nothing extends StatelessWidget {
  const _Nothing();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
