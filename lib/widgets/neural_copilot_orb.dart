import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Futuristic Holographic Neural Orb - An in-car AI driving companion.
/// Features a breathing cyberpunk neon halo, neural core icon,
/// free-floating draggability, and smooth edge-snapping ergonomics.
class NeuralCopilotOrb extends StatefulWidget {
  final VoidCallback onTap;
  final bool initialOnLeft;
  final double initialYFraction;
  final String label;

  const NeuralCopilotOrb({
    super.key,
    required this.onTap,
    this.initialOnLeft = true,
    this.initialYFraction = 0.42,
    this.label = 'NEURO AI',
  });

  @override
  State<NeuralCopilotOrb> createState() => _NeuralCopilotOrbState();
}

class _NeuralCopilotOrbState extends State<NeuralCopilotOrb>
    with TickerProviderStateMixin {
  // Breathing animation controller
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;

  // Edge snap spring animation
  late AnimationController _snapController;
  Animation<Offset>? _snapAnimation;

  Offset? _position;
  double _totalDragDistance = 0.0;
  bool _isDragging = false;

  static const double _orbDiameter = 58.0;
  static const double _edgePadding = 12.0;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.linear),
    );

    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _snapController.addListener(() {
      if (_snapAnimation != null) {
        setState(() {
          _position = _snapAnimation!.value;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_position == null) {
      final size = MediaQuery.of(context).size;
      final initialX = widget.initialOnLeft
          ? _edgePadding
          : (size.width - _orbDiameter - _edgePadding);
      final initialY = size.height * widget.initialYFraction;
      _position = Offset(initialX, initialY);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _snapController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    _snapController.stop();
    _totalDragDistance = 0.0;
    setState(() {
      _isDragging = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Size screenSize) {
    _totalDragDistance += (details.delta.dx.abs() + details.delta.dy.abs());

    setState(() {
      final currentPos = _position ?? Offset.zero;
      final newX = (currentPos.dx + details.delta.dx).clamp(
        4.0,
        screenSize.width - _orbDiameter - 4.0,
      );
      final newY = (currentPos.dy + details.delta.dy).clamp(
        80.0,
        screenSize.height - _orbDiameter - 120.0,
      );
      _position = Offset(newX, newY);
    });
  }

  void _onPanEnd(DragEndDetails details, Size screenSize) {
    setState(() {
      _isDragging = false;
    });

    // If drag was minimal, treat as tap
    if (_totalDragDistance < 8.0) {
      HapticFeedback.lightImpact();
      widget.onTap();
      return;
    }

    final currentPos = _position ?? Offset.zero;
    final centerX = currentPos.dx + (_orbDiameter / 2);
    final targetX = (centerX < screenSize.width / 2)
        ? _edgePadding
        : (screenSize.width - _orbDiameter - _edgePadding);

    final targetY = currentPos.dy.clamp(
      90.0,
      screenSize.height - _orbDiameter - 140.0,
    );

    final startPos = currentPos;
    final endPos = Offset(targetX, targetY);

    _snapAnimation = Tween<Offset>(begin: startPos, end: endPos).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutBack),
    );

    _snapController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final currentPos = _position ??
        Offset(_edgePadding, screenSize.height * widget.initialYFraction);

    return Positioned(
      left: currentPos.dx,
      top: currentPos.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _onPanStart,
        onPanUpdate: (d) => _onPanUpdate(d, screenSize),
        onPanEnd: (d) => _onPanEnd(d, screenSize),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            final pulse = _pulseAnimation.value;
            final scale = _isDragging ? 1.08 : (1.0 + 0.03 * pulse);

            return Transform.scale(
              scale: scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Holographic Sphere Core
                  Container(
                    width: _orbDiameter,
                    height: _orbDiameter,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.2, -0.3),
                        radius: 0.9,
                        colors: [
                          const Color(0xFF00E5FF).withValues(alpha: 0.35),
                          const Color(0xFF0E223D),
                          const Color(0xFF06101E),
                        ],
                        stops: const [0.0, 0.65, 1.0],
                      ),
                      border: Border.all(
                        color: Color.lerp(
                          const Color(0xFF00E5FF),
                          const Color(0xFF80D8FF),
                          pulse,
                        )!,
                        width: 1.8,
                      ),
                      boxShadow: [
                        // Inner halo
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withValues(
                            alpha: 0.35 + 0.30 * pulse,
                          ),
                          blurRadius: 12 + 8 * pulse,
                          spreadRadius: 1 + 2 * pulse,
                        ),
                        // Outer ambient radar glow
                        BoxShadow(
                          color: const Color(0xFF0072FF).withValues(
                            alpha: 0.20 + 0.15 * pulse,
                          ),
                          blurRadius: 22 + 10 * pulse,
                          spreadRadius: 3 + 3 * pulse,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Subtle rotating orbital ring
                        Transform.rotate(
                          angle: _rotationAnimation.value,
                          child: Container(
                            width: _orbDiameter - 8,
                            height: _orbDiameter - 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF00E5FF).withValues(
                                  alpha: 0.25 + 0.25 * pulse,
                                ),
                                width: 1.0,
                              ),
                            ),
                          ),
                        ),

                        // Center AI Brain / Copilot Hologram Icon
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFFE0F7FA), Color(0xFF00E5FF)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ).createShader(bounds),
                          child: const Icon(
                            Icons.psychology_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),

                        // Active Online Neural Dot (Green micro beacon)
                        Positioned(
                          top: 4,
                          right: 6,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E676).withValues(
                                    alpha: 0.6 + 0.4 * pulse,
                                  ),
                                  blurRadius: 6,
                                  spreadRadius: 1.5,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Futuristic Holographic Micro Pill Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06101E).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: const Color(0xFF00E5FF).withValues(
                            alpha: 0.7 + 0.3 * pulse,
                          ),
                          size: 9,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          widget.label,
                          style: const TextStyle(
                            color: Color(0xFF80D8FF),
                            fontSize: 7.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
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
