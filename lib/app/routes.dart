// File: lib/app/routes.dart

import 'package:flutter/material.dart';
import 'package:mb_dental_app/screens/auth/login_screen.dart';
import 'package:mb_dental_app/screens/auth/register_screen.dart';
import 'package:mb_dental_app/screens/dashboard/dashboard_screen.dart';

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

    // Placeholder builders for navigation targets
    appointments: (context) => _buildPlaceholderScreen(context, 'Appointments'),
    wallet: (context) => _buildPlaceholderScreen(context, 'Wallet'),
    records: (context) => _buildPlaceholderScreen(context, 'Records'),
    profile: (context) => _buildPlaceholderScreen(context, 'Profile'),
    notifications: (context) => _buildPlaceholderScreen(context, 'Notifications'),
    bookAppointment: (context) => _buildPlaceholderScreen(context, 'Book Appointment'),
  };

  // Temporary screen builder so navigation works immediately
  static Widget _buildPlaceholderScreen(BuildContext context, String title) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF0D9488),
      ),
      body: Center(
        child: Text(
          '$title Screen',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}