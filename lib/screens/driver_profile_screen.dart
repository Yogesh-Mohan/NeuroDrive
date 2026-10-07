import 'package:flutter/material.dart';
import '../widgets/status_card.dart';
import '../widgets/app_button.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  String _driverName = 'Alex Mercer';
  String _driverEmail = 'alex.mercer@neurodrive.ai';

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: _driverName);
    final emailController = TextEditingController(text: _driverEmail);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Edit Driver Profile', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _driverName = nameController.text;
                _driverEmail = emailController.text;
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: _showEditProfileDialog,
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
                      _driverName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _driverEmail,
                      style: const TextStyle(
                        color: Color(0xFF8892B0),
                        fontSize: 14,
                      ),
                    ),
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

              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  StatusCard(
                    title: 'Total Distance',
                    value: '-- KM',
                    icon: Icons.add_road_rounded,
                    statusColor: primaryColor,
                  ),
                  StatusCard(
                    title: 'Total Time',
                    value: '-- HRS',
                    icon: Icons.timer_outlined,
                    statusColor: const Color(0xFF4A90E2),
                  ),
                  StatusCard(
                    title: 'Safety Score',
                    value: '-- / 100',
                    icon: Icons.star_outline_rounded,
                    statusColor: const Color(0xFF00E676),
                  ),
                  StatusCard(
                    title: 'Alerts Triggered',
                    value: '0',
                    icon: Icons.notifications_none_rounded,
                    statusColor: const Color(0xFFFFB74D),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: 'EDIT PROFILE DETAILS',
                  isSecondary: true,
                  onPressed: _showEditProfileDialog,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
