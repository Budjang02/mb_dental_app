import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app/app.dart';
import 'app/notification_settings.dart';
import 'app/theme_controller.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  String? startupError;
  try {
    // Initialize both backend services
    await Firebase.initializeApp();
    await SupabaseService.initialize();
  } catch (e) {
    startupError = '$e';
    debugPrint('Initialization failed: $e');
  }

  ThemeController().load();
  NotificationSettings().load();

  if (startupError != null) {
    FlutterNativeSplash.remove();
    runApp(StartupFailureApp(message: startupError));
    return;
  }

  runApp(const DentalApp());
}

/// Shown when the app cannot reach its own configuration at launch.
class StartupFailureApp extends StatelessWidget {
  final String message;

  const StartupFailureApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'The app could not start',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}