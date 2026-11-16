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
import 'screens/alert_history_screen.dart';
import 'screens/glasses_screen.dart';
import 'screens/offline_maps_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/vehicle_profile_screen.dart';
import 'screens/emergency_contacts_screen.dart';
import 'screens/v2v_radar_screen.dart';
import 'core/services/notification_service.dart';
import 'core/services/sync_service.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('[NeuroDrive] Firebase initialize notice: $e');
  }

  try {
    await NotificationService().initialize();
  } catch (e) {
    debugPrint('[NeuroDrive] NotificationService initialize notice: $e');
  }

  try {
    SyncService();
  } catch (e) {
    debugPrint('[NeuroDrive] SyncService initialize notice: $e');
  }

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
        AppRoutes.alertHistory: (context) => const AlertHistoryScreen(),
        AppRoutes.alertDetails: (context) => const AlertDetailsScreen(),
        AppRoutes.mapView: (context) => const MainShell(initialTab: 1),
        AppRoutes.settings: (context) => const MainShell(initialTab: 3),
        AppRoutes.glasses: (context) => const GlassesScreen(),
        AppRoutes.offlineMode: (context) => const OfflineMapsScreen(),
        AppRoutes.profile: (context) => const ProfileScreen(),
        AppRoutes.vehicle: (context) => const VehicleProfileScreen(),
        AppRoutes.emergencyContacts: (context) => const EmergencyContactsScreen(),
        AppRoutes.v2vRadar: (context) => const V2VRadarScreen(),
      },
    );
  }
}
