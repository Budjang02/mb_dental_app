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
}