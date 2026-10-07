import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/constants/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'main_shell.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/live_map_screen.dart';
import 'screens/alert_warning_screen.dart';
import 'screens/alert_details_screen.dart';
import 'screens/glasses_screen.dart';
import 'screens/offline_maps_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/vehicle_profile_screen.dart';
import 'core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService().initialize();
  runApp(const NeuroDriveApp());
}

class NeuroDriveApp extends StatelessWidget {
  const NeuroDriveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroDrive',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: AppRoutes.splash,
      routes: {
        AppRoutes.splash: (context) => const SplashScreen(),
        AppRoutes.login: (context) => const LoginScreen(),
        AppRoutes.signup: (context) => const SignupScreen(),
        AppRoutes.mainShell: (context) => const MainShell(),
        AppRoutes.home: (context) => const MainShell(initialTab: 0),
        AppRoutes.liveMap: (context) => const LiveMapScreen(),
        AppRoutes.alertWarning: (context) => const AlertWarningScreen(),
        AppRoutes.tripHistory: (context) => const MainShell(initialTab: 2),
        AppRoutes.alertHistory: (context) => const MainShell(initialTab: 2),
        AppRoutes.alertDetails: (context) => const AlertDetailsScreen(),
        AppRoutes.mapView: (context) => const MainShell(initialTab: 1),
        AppRoutes.settings: (context) => const MainShell(initialTab: 3),
        AppRoutes.glasses: (context) => const GlassesScreen(),
        AppRoutes.offlineMode: (context) => const OfflineMapsScreen(),
        AppRoutes.profile: (context) => const ProfileScreen(),
        AppRoutes.vehicle: (context) => const VehicleProfileScreen(),
      },
    );
  }
}
