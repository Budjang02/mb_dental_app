import 'package:flutter/material.dart';
import 'theme.dart';
import 'theme_controller.dart';
import 'routes.dart';
import '../screens/splash/splash_screen.dart';

class DentalApp extends StatelessWidget {
  const DentalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) {
        return MaterialApp(
          title: 'Mariano & Bolasoc Dental',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeController().mode,
          home: const SplashScreen(),
          routes: AppRoutes.routes,
        );
      },
    );
  }
}
