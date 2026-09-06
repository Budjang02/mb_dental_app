import 'package:flutter/material.dart';
import 'theme.dart';
import 'theme_controller.dart';
import 'routes.dart';
import '../screens/splash/splash_screen.dart';
import '../widgets/push_banner.dart';

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
          // Hosts the real-time alert banner above every route, so a push
          // arriving mid-flow is visible wherever the patient happens to be.
          builder: (context, child) => PushBannerHost(child: child ?? const SizedBox.shrink()),
          home: const SplashScreen(),
          routes: AppRoutes.routes,
        );
      },
    );
  }
}
