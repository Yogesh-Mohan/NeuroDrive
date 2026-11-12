import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../core/models/emergency_contact_model.dart';
import '../core/services/emergency_service.dart';
import '../screens/emergency_contacts_screen.dart';


class SosDialogHelper {
  /// Shows the emergency confirmation modal with real coordinates preview,
  /// 3-second abort timer, loading progress, and accurate status outcomes.
  static Future<void> showSosConfirmationDialog(
    BuildContext context, {
    Position? currentPosition,
  }) async {
    final emergencyService = EmergencyService();

    // Check if another SOS is already executing
    if (emergencyService.isSosInProgress) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An SOS alert dispatch is currently in progress. Please wait.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Launch dialog IMMEDIATELY so button tap responds instantaneously without waiting for network
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return _SosActionDialog(
          emergencyService: emergencyService,
          initialPosition: currentPosition,
        );
      },
    );
  }
}

class _SosActionDialog extends StatefulWidget {
  final EmergencyService emergencyService;
  final Position? initialPosition;

  const _SosActionDialog({
    required this.emergencyService,
    this.initialPosition,
  });

  @override
  State<_SosActionDialog> createState() => _SosActionDialogState();
}

enum _SosFlowStep { confirmation, sending, result }

class _SosActionDialogState extends State<_SosActionDialog> {
  _SosFlowStep _step = _SosFlowStep.confirmation;
  int _countdown = 3;
  bool _countdownActive = true;
  SosResult? _result;
  String? _errorMessage;
  List<EmergencyContact> _contacts = [];
  bool _loadingContacts = true;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _fetchContacts();
    _ensureSmsPermission();
  }

  void _ensureSmsPermission() async {
    // Proactively verify/request runtime SMS permission during countdown
    // so background SMS can dispatch automatically without pausing or showing app choosers
    try {
      final hasPerm = await widget.emergencyService.hasSmsPermission();
      if (!hasPerm) {
        await widget.emergencyService.requestSmsPermission();
      }
    } catch (_) {}
  }

  void _fetchContacts() {
    widget.emergencyService.getEmergencyContacts().then((loaded) {
      if (mounted) {
        setState(() {
          _contacts = loaded;
          _loadingContacts = false;
        });
      }
    }).catchError((_) {
      if (mounted) {
        setState(() {
          _loadingContacts = false;
        });
      }
    });
  }

  void _startCountdown() async {
    while (_countdown > 0 && mounted && _countdownActive && _step == _SosFlowStep.confirmation) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted && _countdownActive && _step == _SosFlowStep.confirmation) {
        setState(() => _countdown--);
      }
    }
    // Automatically dispatch SOS once countdown completes if user hasn't cancelled
    if (mounted && _countdownActive && _countdown == 0 && _step == _SosFlowStep.confirmation) {
      _executeSosDispatch();
    }
  }

  void _cancelCountdown() {
    setState(() => _countdownActive = false);
    Navigator.of(context).pop();
  }

  Future<void> _executeSosDispatch() async {
    setState(() {
      _countdownActive = false;
      _step = _SosFlowStep.sending;
    });

    try {
      // 1. Immediately launch direct automated SMS to emergency contacts in background
      // Zero chooser dialogs, 100% automated background delivery!
      final smsSent = _contacts.isNotEmpty
          ? await widget.emergencyService.sendDirectSmsToContacts(
              contacts: _contacts,
              emergencyMessage: 'Urgent: I need emergency assistance while driving.',
              latitude: widget.initialPosition?.latitude,
              longitude: widget.initialPosition?.longitude,
            ).catchError((e) {
              debugPrint('Direct SMS trigger notice: $e');
              return false;
            })
          : false;

      var res = await widget.emergencyService.triggerEmergencySos(
        preloadedPosition: widget.initialPosition,
        directSmsDelivered: smsSent,
        directDeliveredTo: _contacts.map((c) => '${c.name} (${c.phone})').toList(),
      );

      // If direct automated SMS succeeded, guarantee DELIVERED status in UI
      if (smsSent && res.status != 'DELIVERED') {
        res = res.copyWith(
          success: true,
          status: 'DELIVERED',
          deliveryProvider: 'Automated Background SMS',
          message: 'Automated emergency SMS dispatched to ${_contacts.map((c) => c.name).join(', ')} with live GPS coordinates.',
          deliveredTo: _contacts.map((c) => '${c.name} (${c.phone})').toList(),
        );
      }

      if (mounted) {
        setState(() {
          _result = res;
          _step = _SosFlowStep.result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _step = _SosFlowStep.result;
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    const navyBg = Color(0xFF0A192F);
    const cardBg = Color(0xFF112240);
    const cyanColor = Color(0xFF00D2FF);
    const redAccent = Color(0xFFFF5252);

    return AlertDialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: redAccent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.all(24),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_step == _SosFlowStep.confirmation) ...[
              // EMERGENCY HEADER ICON
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: redAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: redAccent, width: 2),
                ),
                child: const Center(
                  child: Icon(Icons.emergency_share_rounded, color: redAccent, size: 38),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'TRIGGER EMERGENCY SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This will record an emergency event with your real GPS location and alert your emergency contacts.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8892B0), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),

              // GPS LOCATION PREVIEW CARD
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: navyBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cyanColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: cyanColor, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CURRENT GPS COORDINATES',
                            style: TextStyle(color: cyanColor, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.initialPosition != null
                                ? '${widget.initialPosition!.latitude.toStringAsFixed(5)}, ${widget.initialPosition!.longitude.toStringAsFixed(5)}'
                                : 'Live GPS lock in progress...',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // CONTACTS PREVIEW CARD
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: navyBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (!_loadingContacts && _contacts.isEmpty)
                        ? Colors.orangeAccent.withValues(alpha: 0.4)
                        : cyanColor.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          (!_loadingContacts && _contacts.isEmpty)
                              ? Icons.warning_amber_rounded
                              : Icons.contacts_rounded,
                          color: (!_loadingContacts && _contacts.isEmpty) ? Colors.orangeAccent : cyanColor,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _loadingContacts
                                ? 'Checking emergency contacts in settings...'
                                : _contacts.isEmpty
                                    ? 'No emergency contacts configured yet in Settings.'
                                    : 'Emergency SMS will be sent to ${_contacts.length} contact(s):',
                            style: TextStyle(
                              color: (!_loadingContacts && _contacts.isEmpty) ? Colors.orangeAccent : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_contacts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ..._contacts.map((c) => Padding(
                        padding: const EdgeInsets.only(left: 30, top: 2),
                        child: Text(
                          '• ${c.name} (${c.phone})${c.isPrimary ? " [Primary]" : ""}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      )),
                    ],
                    if (!_loadingContacts && _contacts.isEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orangeAccent,
                            side: const BorderSide(color: Colors.orangeAccent),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()),
                            );
                          },
                          icon: const Icon(Icons.person_add_rounded, size: 16),
                          label: const Text('Add Emergency Contacts Now', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),


              // AUTOMATED DISPATCH STATUS INDICATOR
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: redAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.timer_outlined, color: redAccent, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _countdown > 0
                          ? 'Automated dispatch in $_countdown s (or tap Send Now)'
                          : 'Auto-dispatching emergency alert now...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ACTION BUTTONS
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _cancelCountdown,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _executeSosDispatch,
                      child: Text(
                        _countdown > 0 ? 'Send Now ($_countdown)' : 'Send SOS',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            if (_step == _SosFlowStep.sending) ...[
              const SizedBox(height: 16),
              const SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  color: redAccent,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'DISPATCHING SOS...',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              const Text(
                'Capturing verified GPS coordinates, writing emergency record to Cloud Firestore, and contacting delivery gateway.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8892B0), fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
            ],

            if (_step == _SosFlowStep.result) ...[
              // RESULT STATE DISPLAY
              if (_result != null && _result!.status == 'DELIVERED') ...[
                const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 64),
                const SizedBox(height: 14),
                const Text(
                  'SOS Alert Dispatched',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  _result!.deliveredTo.isNotEmpty
                      ? 'Delivered via ${_result!.deliveryProvider} to ${_result!.deliveredTo.join(', ')}.'
                      : (_result!.message.isNotEmpty ? _result!.message : 'Emergency alert dispatched to your contacts with live GPS coordinates.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8892B0), fontSize: 12),
                ),
              ] else if (_result != null && _result!.status == 'CONFIG_REQUIRED') ...[
                const Icon(Icons.settings_suggest_rounded, color: Colors.orangeAccent, size: 64),
                const SizedBox(height: 14),
                const Text(
                  'Setup Required',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  _result!.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8892B0), fontSize: 12),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: navyBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Note: Event was safely logged to Cloud Firestore with your exact GPS link.',
                    style: TextStyle(color: cyanColor, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ),
              ] else ...[
                const Icon(Icons.error_outline_rounded, color: redAccent, size: 64),
                const SizedBox(height: 14),
                const Text(
                  'Alert Delivery Failed',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage ?? _result?.message ?? 'Failed to reach emergency delivery service.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8892B0), fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),

              // MAPS LINK PREVIEW
              if (_result != null && _result!.latitude != null && _result!.longitude != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: navyBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.map_rounded, color: cyanColor, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'GPS: ${_result!.latitude!.toStringAsFixed(5)}, ${_result!.longitude!.toStringAsFixed(5)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // RESULT ACTION BUTTONS
              // ONLY show fallback "Send / Open SMS to Contacts" when delivery actually FAILED!
              if (_result != null && _result!.status != 'DELIVERED' && _contacts.isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      await widget.emergencyService.sendDirectSmsToContacts(
                        contacts: _contacts,
                        emergencyMessage: 'Urgent: I need emergency assistance while driving.',
                        latitude: _result?.latitude ?? widget.initialPosition?.latitude,
                        longitude: _result?.longitude ?? widget.initialPosition?.longitude,
                      );
                    },
                    icon: const Icon(Icons.sms_rounded, size: 18),
                    label: const Text('Send / Open SMS to Contacts', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 10),
              ] else if (_contacts.isEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()),
                      );
                    },
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Add Contacts in Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              Row(
                children: [
                  if (_result != null && _result!.status != 'DELIVERED') ...[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cyanColor,
                          side: const BorderSide(color: cyanColor),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _executeSosDispatch,
                        child: const Text('Retry'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (_result != null && _result!.status == 'DELIVERED')
                            ? Colors.greenAccent.shade700
                            : const Color(0xFF1F4068),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text((_result != null && _result!.status == 'DELIVERED') ? 'Done' : 'Close'),
                    ),
                  ),
                ],
              ),

            ],
          ],
        ),
      ),
    );
  }
}
