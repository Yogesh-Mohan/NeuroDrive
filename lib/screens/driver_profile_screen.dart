import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/status_card.dart';
import '../widgets/app_button.dart';
import '../core/models/user_profile_model.dart';
import '../core/models/trip_model.dart';
import '../core/models/alert_model.dart';
import '../core/services/auth_service.dart';
import '../core/services/trip_service.dart';
import '../core/services/alert_service.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final AuthService _authService = AuthService();
  final TripService _tripService = TripService();
  final AlertService _alertService = AlertService();
  bool _isSaving = false;

  void _showEditProfileDialog(String currentName, String currentEmail, String currentPhone) {
    final nameController = TextEditingController(text: currentName);
    final emailController = TextEditingController(text: currentEmail);
    final phoneController = TextEditingController(text: currentPhone);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: !_isSaving,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Edit Driver Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      enabled: !_isSaving,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Name *'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailController,
                      enabled: !_isSaving,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email *'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Email is required';
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v.trim())) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneController,
                      enabled: !_isSaving,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone Number'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (!_isSaving)
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
              ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : () async {
                        if (formKey.currentState!.validate()) {
                          setStateDialog(() => _isSaving = true);
                          try {
                            await _authService.updateDriverProfile(
                              name: nameController.text.trim(),
                              email: emailController.text.trim(),
                              phone: phoneController.text.trim(),
                            );
                            if (mounted && dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Driver profile saved!'),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted && dialogCtx.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to save profile: ${e.toString().replaceAll('Exception: ', '')}'),
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setStateDialog(() => _isSaving = false);
                          }
                        }
                      },
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final currentUser = _authService.currentUser;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _authService.getUserProfileStream(),
      builder: (context, snapshot) {
        final profile = snapshot.hasData && snapshot.data != null
            ? UserProfile.fromFirestore(
                snapshot.data!,
                fallbackEmail: currentUser?.email,
                fallbackName: currentUser?.displayName,
              )
            : UserProfile(
                uid: currentUser?.uid ?? '',
                name: currentUser?.displayName ?? 'Alex Mercer',
                email: currentUser?.email ?? 'alex.mercer@neurodrive.ai',
              );

        final driverName = profile.name.isNotEmpty
            ? profile.name
            : (currentUser?.displayName ?? 'Alex Mercer');
        final driverEmail = profile.email.isNotEmpty
            ? profile.email
            : (currentUser?.email ?? 'alex.mercer@neurodrive.ai');
        final driverPhone = profile.phone;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Driver Profile'),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _showEditProfileDialog(driverName, driverEmail, driverPhone),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Profile Header Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 46,
                              backgroundColor: primaryColor.withValues(alpha: 0.15),
                              child: Icon(
                                Icons.person_rounded,
                                size: 50,
                                color: primaryColor,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: primaryColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.verified_user_rounded,
                                  size: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          driverName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          driverEmail,
                          style: const TextStyle(
                            color: Color(0xFF8892B0),
                            fontSize: 14,
                          ),
                        ),
                        if (driverPhone.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            driverPhone,
                            style: const TextStyle(
                              color: Color(0xFF8892B0),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Driving Statistics Overview
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Driving Statistics',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  StreamBuilder<List<TripModel>>(
                    stream: _tripService.getTripsStream(),
                    builder: (context, tripSnapshot) {
                      final trips = tripSnapshot.data ?? [];
                      final double totalDistanceMeters = trips.fold(0.0, (acc, t) => acc + t.distance);
                      final int totalDurationSeconds = trips.fold(0, (acc, t) => acc + t.duration);
                      
                      final totalDistanceKm = (totalDistanceMeters / 1000).toStringAsFixed(1);
                      final double totalHours = totalDurationSeconds / 3600;
                      final totalTimeStr = totalHours >= 1.0 
                          ? '${totalHours.toStringAsFixed(1)} HRS' 
                          : '${(totalDurationSeconds ~/ 60)} MIN';

                      return GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.5,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          StatusCard(
                            title: 'Total Distance',
                            value: trips.isEmpty ? '0.0 KM' : '$totalDistanceKm KM',
                            icon: Icons.add_road_rounded,
                            statusColor: primaryColor,
                          ),
                          StatusCard(
                            title: 'Total Time',
                            value: trips.isEmpty ? '0 MIN' : totalTimeStr,
                            icon: Icons.timer_outlined,
                            statusColor: const Color(0xFF4A90E2),
                          ),
                          StatusCard(
                            title: 'Trips Completed',
                            value: '${trips.length}',
                            icon: Icons.alt_route_rounded,
                            statusColor: const Color(0xFF4A90E2),
                          ),
                          StreamBuilder<List<AlertModel>>(
                            stream: _alertService.getAlertsStream(),
                            builder: (context, alertSnapshot) {
                              final alertCount = alertSnapshot.data?.length ?? 0;
                              return StatusCard(
                                title: 'Alerts Triggered',
                                value: '$alertCount',
                                icon: Icons.notifications_none_rounded,
                                statusColor: alertCount > 0 ? const Color(0xFFFFB74D) : const Color(0xFF00E676),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      label: 'EDIT PROFILE DETAILS',
                      isSecondary: true,
                      onPressed: () => _showEditProfileDialog(driverName, driverEmail, driverPhone),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
