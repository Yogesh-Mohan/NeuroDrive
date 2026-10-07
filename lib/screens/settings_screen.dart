import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_routes.dart';
import '../core/services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  late SharedPreferences _prefs;
  
  bool _isLoading = true;
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = true;
  String _distanceUnit = 'km';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      setState(() {
        _notificationsEnabled = _prefs.getBool('notifications_enabled') ?? true;
        _darkModeEnabled = _prefs.getBool('dark_mode_enabled') ?? true;
        _distanceUnit = _prefs.getString('distance_unit') ?? 'km';
        _isLoading = false;
      });
    } catch (e) {
      // Fallback defaults on error
      setState(() {
        _isLoading = false;
      });
      debugPrint('Error loading preferences: $e');
    }
  }

  Future<void> _saveBoolPref(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  Future<void> _saveStringPref(String key, String value) async {
    await _prefs.setString(key, value);
  }

  void _showAppPreferencesDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: const Color(0xFF112240),
            title: const Text('App Preferences', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Dark Mode', style: TextStyle(color: Colors.white)),
                  value: _darkModeEnabled,
                  activeTrackColor: const Color(0xFF00D2FF),
                  onChanged: (val) {
                    setStateDialog(() => _darkModeEnabled = val);
                    setState(() => _darkModeEnabled = val);
                    _saveBoolPref('dark_mode_enabled', val);
                  },
                ),
                ListTile(
                  title: const Text('Distance Unit', style: TextStyle(color: Colors.white)),
                  trailing: DropdownButton<String>(
                    dropdownColor: const Color(0xFF0A192F),
                    value: _distanceUnit,
                    style: const TextStyle(color: Color(0xFF00D2FF)),
                    items: const [
                      DropdownMenuItem(value: 'km', child: Text('Kilometers')),
                      DropdownMenuItem(value: 'mi', child: Text('Miles')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setStateDialog(() => _distanceUnit = val);
                        setState(() => _distanceUnit = val);
                        _saveStringPref('distance_unit', val);
                      }
                    },
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showAlertSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: const Color(0xFF112240),
            title: const Text('Alert Settings', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Enable Notifications', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Receive driving alerts', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  value: _notificationsEnabled,
                  activeTrackColor: const Color(0xFF00D2FF),
                  onChanged: (val) {
                    setStateDialog(() => _notificationsEnabled = val);
                    setState(() => _notificationsEnabled = val);
                    _saveBoolPref('notifications_enabled', val);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D2FF);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            _buildSettingTile(
              icon: Icons.person_outline_rounded,
              title: 'Driver Profile',
              onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
              primaryColor: primaryColor,
            ),
            _buildSettingTile(
              icon: Icons.directions_car_rounded,
              title: 'Vehicle Profile',
              onTap: () => Navigator.pushNamed(context, AppRoutes.vehicle),
              primaryColor: primaryColor,
            ),
            _buildSettingTile(
              icon: Icons.tune_rounded,
              title: 'App Preferences',
              subtitle: 'Theme, Distance Unit',
              onTap: _showAppPreferencesDialog,
              primaryColor: primaryColor,
            ),
            _buildSettingTile(
              icon: Icons.notifications_none_rounded,
              title: 'Alert Settings',
              subtitle: _notificationsEnabled ? 'Notifications ON' : 'Notifications OFF',
              onTap: _showAlertSettingsDialog,
              primaryColor: primaryColor,
            ),
            _buildSettingTile(
              icon: Icons.map_outlined,
              title: 'Map Settings',
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Map Settings: Coming soon'))),
              primaryColor: primaryColor,
            ),
            _buildSettingTile(
              icon: Icons.cloud_download_outlined,
              title: 'Offline Maps',
              onTap: () => Navigator.pushNamed(context, AppRoutes.offlineMode),
              primaryColor: primaryColor,
            ),
            _buildSettingTile(
              icon: Icons.bluetooth_rounded,
              title: 'Bluetooth (Glasses)',
              subtitle: 'Not Connected',
              onTap: () => Navigator.pushNamed(context, AppRoutes.glasses),
              primaryColor: primaryColor,
            ),
            _buildSettingTile(
              icon: Icons.storage_rounded,
              title: 'Data & Storage',
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data & Storage: Coming soon'))),
              primaryColor: primaryColor,
            ),
            _buildSettingTile(
              icon: Icons.help_outline_rounded,
              title: 'Help & Support',
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Help & Support: Coming soon'))),
              primaryColor: primaryColor,
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: const Text('Logout', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    title: const Text('Confirm Logout', style: TextStyle(color: Colors.white)),
                    content: const Text(
                      'Are you sure you want to log out of NeuroDrive?',
                      style: TextStyle(color: Color(0xFF8892B0)),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5252)),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await _authService.signOut();
                  if (context.mounted) {
                    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    required Color primaryColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF112240),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Icon(icon, color: primaryColor),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(color: Color(0xFF8892B0), fontSize: 12)) : null,
        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF8892B0)),
        onTap: onTap,
      ),
    );
  }
}
