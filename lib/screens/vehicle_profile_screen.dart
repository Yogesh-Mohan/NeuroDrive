import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/status_card.dart';
import '../widgets/app_button.dart';
import '../core/models/user_profile_model.dart';
import '../core/services/auth_service.dart';

class VehicleProfileScreen extends StatefulWidget {
  const VehicleProfileScreen({super.key});

  @override
  State<VehicleProfileScreen> createState() => _VehicleProfileScreenState();
}

class _VehicleProfileScreenState extends State<VehicleProfileScreen> {
  final AuthService _authService = AuthService();
  bool _isSaving = false;

  void _showEditVehicleDialog({
    required String currentName,
    required String currentPlate,
    required String currentType,
    required String currentModel,
  }) {
    final nameCtrl = TextEditingController(text: currentName == 'Unknown Vehicle' ? '' : currentName);
    final plateCtrl = TextEditingController(text: currentPlate == 'NO-PLATE' ? '' : currentPlate);
    final typeCtrl = TextEditingController(text: currentType == 'Unknown Type' ? '' : currentType);
    final modelCtrl = TextEditingController(text: currentModel == 'Unknown Model' ? '' : currentModel);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: !_isSaving,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Edit Vehicle Info', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      enabled: !_isSaving,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Name *',
                        hintText: 'e.g. My Honda Civic',
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Vehicle name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: plateCtrl,
                      enabled: !_isSaving,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Registration Number *',
                        hintText: 'e.g. MH12 AB 1234',
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Registration number is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: typeCtrl,
                      enabled: !_isSaving,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Type *',
                        hintText: 'e.g. Sedan, SUV, EV',
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Vehicle type is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: modelCtrl,
                      enabled: !_isSaving,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Model *',
                        hintText: 'e.g. 2024 V Turbo',
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Vehicle model is required';
                        }
                        return null;
                      },
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
                            await _authService.updateVehicleInfo(
                              name: nameCtrl.text.trim(),
                              number: plateCtrl.text.trim(),
                              type: typeCtrl.text.trim(),
                              model: modelCtrl.text.trim(),
                            );
                            if (mounted && dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Vehicle info saved!'),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted && dialogCtx.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to save vehicle: ${e.toString().replaceAll('Exception: ', '')}'),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle Profile')),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _authService.getUserProfileStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      Text("Failed to load vehicle data: ${snapshot.error}",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              );
            }

            final data = snapshot.data?.data();
            final vehicleMap = data?['vehicle'] is Map<String, dynamic>
                ? data!['vehicle'] as Map<String, dynamic>
                : (data?['vehicle'] is Map ? Map<String, dynamic>.from(data!['vehicle'] as Map) : null);
            final vehicle = VehicleModel.fromMap(vehicleMap);

            final vName = vehicle.name.isNotEmpty ? vehicle.name : 'Unknown Vehicle';
            final vNumber = vehicle.registrationNumber.isNotEmpty ? vehicle.registrationNumber : 'NO-PLATE';
            final vType = vehicle.type.isNotEmpty ? vehicle.type : 'Unknown Type';
            final vModel = vehicle.model.isNotEmpty ? vehicle.model : 'Unknown Model';

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.directions_car_rounded, size: 54, color: primaryColor),
                        ),
                        const SizedBox(height: 16),
                        Text(vName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(vNumber, style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text('Vehicle Specifications', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),

                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 1.5,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      StatusCard(title: 'Type', value: vType, icon: Icons.electric_car_rounded, statusColor: primaryColor),
                      StatusCard(title: 'Model', value: vModel, icon: Icons.car_repair_rounded, statusColor: const Color(0xFFFFB74D)),
                      StatusCard(title: 'Smart Glass', value: 'Not Paired', icon: Icons.visibility_outlined, statusColor: const Color(0xFF8892B0)),
                      StatusCard(title: 'Health Score', value: '--', icon: Icons.health_and_safety_outlined, statusColor: const Color(0xFF00E676)),
                    ],
                  ),

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      label: 'UPDATE VEHICLE INFO',
                      isSecondary: true,
                      onPressed: () => _showEditVehicleDialog(
                        currentName: vName,
                        currentPlate: vNumber,
                        currentType: vType,
                        currentModel: vModel,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
