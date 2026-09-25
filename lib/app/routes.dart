// File: lib/app/routes.dart
import 'package:flutter/material.dart';
import 'package:mb_dental_app/screens/auth/login_screen.dart';
import 'package:mb_dental_app/screens/auth/register_screen.dart';
import 'package:mb_dental_app/screens/dashboard/dashboard_screen.dart';
import 'package:mb_dental_app/screens/appointments/appointments_screen.dart';
import 'package:mb_dental_app/screens/appointments/book_appointment_screen.dart';
import 'package:mb_dental_app/screens/wallet/wallet_screen.dart';
import 'package:mb_dental_app/screens/records/dental_records_screen.dart';
import 'package:mb_dental_app/screens/profile/profile_screen.dart';
import 'package:mb_dental_app/screens/dashboard/notifications_screen.dart';
import 'package:mb_dental_app/services/supabase_service.dart';

class AppRoutes {
  static const String login = '/login';
  static const String register = '/register';
  static const String dashboard = '/dashboard';
  static const String appointments = '/appointments';
  static const String wallet = '/wallet';
  static const String records = '/records';
  static const String profile = '/profile';
  static const String notifications = '/notifications';
  static const String bookAppointment = '/book-appointment';

  /// The routes that show a patient their own data. Reaching one of these
  /// without a session would leave the screen asking Supabase for rows it has
  /// no JWT for, so the guard in [onGenerateRoute] sends them to Login first.
  static const Set<String> protected = {
    dashboard,
    appointments,
    wallet,
    records,
    profile,
    notifications,
    bookAppointment,
  };

  static Map<String, WidgetBuilder> get routes => {
    login: (context) => const LoginScreen(),
    register: (context) => const RegisterScreen(),
    dashboard: (context) => const DashboardScreen(),
    appointments: (context) => const AppointmentsScreen(),
    wallet: (context) => const WalletScreen(),
    records: (context) => const DentalRecordsScreen(),
    profile: (context) => const ProfileScreen(),
    bookAppointment: (context) => const BookAppointmentScreen(),
    notifications: (context) => const NotificationsScreen(),
  };

  /// Builds every named route, refusing a protected one while signed out.
  ///
  /// The screens themselves are the ones that would otherwise be wrong: the
  /// dashboard's tabs each ask [PatientRepository] for records, and with no
  /// session those requests are refused rather than answered. Sending the
  /// patient to Login instead is the whole of the check — it is not a
  /// substitute for row-level security, which is what actually keeps one
  /// patient out of another's rows.
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final name = settings.name;
    final builder = routes[name];
    if (builder == null) return null;

    if (protected.contains(name) && !SupabaseService.isSignedIn) {
      // Named as Login, so a later `pushNamedAndRemoveUntil(login)` — what the
      // sign-out listener does — matches it rather than stacking a second one.
      return MaterialPageRoute(
        settings: const RouteSettings(name: login),
        builder: (context) => const LoginScreen(),
      );
    }
    return MaterialPageRoute(settings: settings, builder: builder);
  }
}
