import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/models/user_profile_model.dart';
import '../core/services/auth_service.dart';
import '../core/constants/app_routes.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  bool _isSaving = false;

  void _showEditProfileDialog(
    BuildContext context, {
    required String currentName,
    required String currentEmail,
    required String currentPhone,
  }) {
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
            title: const Text('Edit Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Full name is required';
                        }
                        if (v.trim().length < 2) {
                          return 'Name must be at least 2 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: emailController,
                      enabled: !_isSaving,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email Address *',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Email is required';
                        }
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v.trim())) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: phoneController,
                      enabled: !_isSaving,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
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
                                  content: Text('Profile saved successfully!'),
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
    const primaryColor = Color(0xFF00D2FF);
    final currentUser = _authService.currentUser;

    if (currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _authService.getUserProfileStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final profile = snapshot.hasData && snapshot.data != null
                ? UserProfile.fromFirestore(
                    snapshot.data!,
                    fallbackEmail: currentUser.email,
                    fallbackName: currentUser.displayName,
                  )
                : UserProfile(
                    uid: currentUser.uid,
                    name: currentUser.displayName ?? 'NeuroDrive Driver',
                    email: currentUser.email ?? '--',
                  );

            final String displayName = profile.name.isNotEmpty
                ? profile.name
                : (currentUser.displayName ?? 'NeuroDrive Driver');
            final String displayEmail = profile.email.isNotEmpty
                ? profile.email
                : (currentUser.email ?? '--');
            final String phone = profile.phone;

            final dateFormat = DateFormat('MMM d, yyyy • h:mm a');
            final String? createdDateStr = profile.createdAt != null
                ? dateFormat.format(profile.createdAt!.toLocal())
                : null;
            final String? updatedDateStr = profile.updatedAt != null
                ? dateFormat.format(profile.updatedAt!.toLocal())
                : null;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    children: [
                      const CircleAvatar(
                        radius: 46,
                        backgroundColor: Color(0xFF112240),
                        child: Icon(Icons.person_rounded, size: 54, color: primaryColor),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.verified_user_rounded, size: 14, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(displayEmail, style: const TextStyle(color: Color(0xFF8892B0), fontSize: 14)),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(phone, style: const TextStyle(color: Color(0xFF8892B0), fontSize: 14)),
                  ],
                  const SizedBox(height: 24),

                  // Metadata Card (createdAt, updatedAt)
                  if (createdDateStr != null || updatedDateStr != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF112240).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF233554)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (createdDateStr != null) ...[
                            Row(
                              children: [
                                const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF8892B0)),
                                const SizedBox(width: 8),
                                const Text('Member since: ', style: TextStyle(color: Color(0xFF8892B0), fontSize: 12)),
                                Expanded(
                                  child: Text(
                                    createdDateStr,
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (createdDateStr != null && updatedDateStr != null) const SizedBox(height: 8),
                          if (updatedDateStr != null) ...[
                            Row(
                              children: [
                                const Icon(Icons.update_rounded, size: 14, color: Color(0xFF8892B0)),
                                const SizedBox(width: 8),
                                const Text('Last updated: ', style: TextStyle(color: Color(0xFF8892B0), fontSize: 12)),
                                Expanded(
                                  child: Text(
                                    updatedDateStr,
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Action Options
                  _buildOptionTile(Icons.person_outline_rounded, 'Edit Profile', () {
                    _showEditProfileDialog(
                      context,
                      currentName: displayName,
                      currentEmail: displayEmail,
                      currentPhone: phone,
                    );
                  }),
                  _buildOptionTile(Icons.contact_phone_outlined, 'Emergency Contacts', () {
                    Navigator.pushNamed(context, AppRoutes.emergencyContacts);
                  }),
                  _buildOptionTile(Icons.logout_rounded, 'Logout', () async {
                    await _authService.signOut();
                    if (context.mounted) Navigator.of(context).pushReplacementNamed(AppRoutes.login);
                  }, isDanger: true),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildOptionTile(IconData icon, String title, VoidCallback onTap, {bool isDanger = false}) {
    final color = isDanger ? Colors.redAccent : Colors.white;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF112240),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Icon(icon, color: isDanger ? Colors.redAccent : const Color(0xFF00D2FF)),
        title: Text(title, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF8892B0)),
        onTap: onTap,
      ),
    );
  }
}
