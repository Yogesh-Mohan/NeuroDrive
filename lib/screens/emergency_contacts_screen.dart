import 'package:flutter/material.dart';
import '../core/models/emergency_contact_model.dart';
import '../core/services/emergency_service.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final EmergencyService _emergencyService = EmergencyService();
  bool _isSaving = false;
  bool _hasSmsPermission = true;

  @override
  void initState() {
    super.initState();
    _checkSmsPermission();
  }

  Future<void> _checkSmsPermission() async {
    final granted = await _emergencyService.hasSmsPermission();
    if (mounted) {
      setState(() {
        _hasSmsPermission = granted;
      });
    }
  }

  Future<void> _requestSmsPermission() async {
    final granted = await _emergencyService.requestSmsPermission();
    if (mounted) {
      setState(() {
        _hasSmsPermission = granted;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? 'Automated background SMS dispatch enabled!'
                : 'SMS permission not granted. Emergency SMS may prompt an app chooser.',
          ),
          backgroundColor: granted ? Colors.green.shade800 : Colors.orange.shade800,
        ),
      );
    }
  }

  void _showAddEditContactDialog({EmergencyContact? contact}) {
    final nameController = TextEditingController(text: contact?.name ?? '');
    final phoneController = TextEditingController(text: contact?.phone ?? '');
    String relationship = contact?.relationship ?? 'Family';
    bool isPrimary = contact?.isPrimary ?? false;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: !_isSaving,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: const Color(0xFF112240),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              contact == null ? 'Add Emergency Contact' : 'Edit Contact',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Contact Name *',
                        labelStyle: const TextStyle(color: Color(0xFF8892B0)),
                        prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF00D2FF)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF00D2FF)),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Name is required';
                        if (v.trim().length < 2) return 'At least 2 characters required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: phoneController,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Phone Number *',
                        labelStyle: const TextStyle(color: Color(0xFF8892B0)),
                        prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFF00D2FF)),
                        hintText: '+91 98765 43210',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF00D2FF)),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Phone number is required';
                        final clean = v.replaceAll(RegExp(r'[\s\-\(\)]'), '');
                        if (clean.length < 5) return 'Enter a valid phone number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: relationship,
                      dropdownColor: const Color(0xFF0A192F),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Relationship',
                        labelStyle: const TextStyle(color: Color(0xFF8892B0)),
                        prefixIcon: const Icon(Icons.group_outlined, color: Color(0xFF00D2FF)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF00D2FF)),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Family', child: Text('Family')),
                        DropdownMenuItem(value: 'Spouse', child: Text('Spouse')),
                        DropdownMenuItem(value: 'Parent', child: Text('Parent')),
                        DropdownMenuItem(value: 'Sibling', child: Text('Sibling')),
                        DropdownMenuItem(value: 'Friend', child: Text('Friend')),
                        DropdownMenuItem(value: 'Doctor', child: Text('Doctor')),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (val) {
                        if (val != null) setStateDialog(() => relationship = val);
                      },
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Primary Contact', style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: const Text(
                        'Will be highlighted during emergency dispatch',
                        style: TextStyle(color: Color(0xFF8892B0), fontSize: 11),
                      ),
                      value: isPrimary,
                      activeColor: const Color(0xFF00D2FF),
                      onChanged: (val) => setStateDialog(() => isPrimary = val ?? false),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: _isSaving ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF8892B0))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D2FF),
                  foregroundColor: const Color(0xFF0A192F),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setStateDialog(() => _isSaving = true);
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await _emergencyService.saveEmergencyContact(
                            id: contact?.id,
                            name: nameController.text.trim(),
                            phone: phoneController.text.trim(),
                            relationship: relationship,
                            isPrimary: isPrimary,
                          );
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(contact == null ? 'Emergency contact added' : 'Contact updated'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } catch (e) {
                          setStateDialog(() => _isSaving = false);
                          messenger.showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                          );
                        }
                      },
                child: _isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save Contact', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteContact(EmergencyContact contact) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF112240),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Contact?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to remove ${contact.name} from your emergency contacts?',
          style: const TextStyle(color: Color(0xFF8892B0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8892B0))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5252)),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _emergencyService.deleteEmergencyContact(contact.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Contact removed'), backgroundColor: Colors.orange),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D2FF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: primaryColor),
            tooltip: 'Add Contact',
            onPressed: () => _showAddEditContactDialog(),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<EmergencyContact>>(
          stream: _emergencyService.getEmergencyContactsStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final contacts = snapshot.data ?? [];

            if (contacts.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.contact_phone_outlined, size: 56, color: Colors.redAccent),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No Emergency Contacts',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Add contacts who should receive urgent alerts and your real-time GPS location when you trigger SOS.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF8892B0), fontSize: 13, height: 1.5),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add First Contact'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: const Color(0xFF0A192F),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _showAddEditContactDialog(),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: [
                if (!_hasSmsPermission)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.sms_failed_rounded, color: Colors.orangeAccent, size: 24),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SMS Permission Required',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Enable direct background SMS so SOS alerts send automatically without app choosers.',
                                style: TextStyle(color: Color(0xFF8892B0), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _requestSmsPermission,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.orangeAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          child: const Text('ENABLE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: contacts.length,
                    itemBuilder: (context, index) {
                      final c = contacts[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF112240),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: c.isPrimary ? primaryColor.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.05),
                            width: c.isPrimary ? 1.5 : 1,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: c.isPrimary ? primaryColor.withValues(alpha: 0.2) : Colors.white12,
                            child: Icon(
                              c.isPrimary ? Icons.star_rounded : Icons.person_rounded,
                              color: c.isPrimary ? primaryColor : Colors.white70,
                            ),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  c.name,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (c.isPrimary) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'PRIMARY',
                                    style: TextStyle(color: primaryColor, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(c.phone, style: const TextStyle(color: Color(0xFF00D2FF), fontSize: 13)),
                              const SizedBox(height: 2),
                              Text(c.relationship, style: const TextStyle(color: Color(0xFF8892B0), fontSize: 12)),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
                                onPressed: () => _showAddEditContactDialog(contact: c),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                onPressed: () => _confirmDeleteContact(c),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
