import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/status_card.dart';
import '../widgets/app_button.dart';
import '../core/services/auth_service.dart';

class VehicleProfileScreen extends StatefulWidget {
  const VehicleProfileScreen({super.key});

  @override
  State<VehicleProfileScreen> createState() => _VehicleProfileScreenState();
}

class _VehicleProfileScreenState extends State<VehicleProfileScreen> {
  final AuthService _authService = AuthService();
  bool _isSaving = false;

  void _showEditVehicleDialog(String currentName, String currentPlate, String currentType, String currentModel) {
    final nameCtrl = TextEditingController(text: currentName);
    final plateCtrl = TextEditingController(text: currentPlate);
    final typeCtrl = TextEditingController(text: currentType);
    final modelCtrl = TextEditingController(text: currentModel);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: const Text('Edit Vehicle Info', style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Vehicle Name (e.g. My Honda)')),
                  const SizedBox(height: 12),
                  TextField(controller: plateCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Registration Number')),
                  const SizedBox(height: 12),
                  TextField(controller: typeCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Type (e.g. Sedan, SUV)')),
                  const SizedBox(height: 12),
                  TextField(controller: modelCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Model (e.g. 2023 Civic)')),
                ],
              ),
            ),
            actions: [
              if (!_isSaving)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ElevatedButton(
                onPressed: _isSaving 
                  ? null 
                  : () async {
                      setStateDialog(() => _isSaving = true);
                      try {
                        await _authService.updateVehicleInfo(
                          name: nameCtrl.text,
                          number: plateCtrl.text,
                          type: typeCtrl.text,
                          model: modelCtrl.text,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Vehicle info saved!'), backgroundColor: Colors.green),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        if (mounted) setStateDialog(() => _isSaving = false);
                      }
                  },
                child: _isSaving 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save'),
              ),
            ],
          );
        }
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
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData || snapshot.data?.data() == null) {
              return const Center(child: Text("Failed to load vehicle data.", style: TextStyle(color: Colors.white)));
            }

            final data = snapshot.data!.data()!;
            final vehicle = data['vehicle'] as Map<String, dynamic>? ?? {};
            
            final vName = vehicle['name']?.toString().isNotEmpty == true ? vehicle['name'] : 'Unknown Vehicle';
            final vNumber = vehicle['number']?.toString().isNotEmpty == true ? vehicle['number'] : 'NO-PLATE';
            final vType = vehicle['type']?.toString().isNotEmpty == true ? vehicle['type'] : 'Unknown Type';
            final vModel = vehicle['model']?.toString().isNotEmpty == true ? vehicle['model'] : 'Unknown Model';

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
                      onPressed: () => _showEditVehicleDialog(vName, vNumber, vType, vModel),
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
