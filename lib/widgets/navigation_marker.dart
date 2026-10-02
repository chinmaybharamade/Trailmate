import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../core/theme.dart';
import '../core/app_colors.dart';

class GoogleNavigationMarker extends StatefulWidget {
  final double heading;
  final Duration? animationDuration;

  GoogleNavigationMarker({
    super.key,
    required this.heading,
    this.animationDuration,
  });

  @override
  State<GoogleNavigationMarker> createState() => _GoogleNavigationMarkerState();
}

class _GoogleNavigationMarkerState extends State<GoogleNavigationMarker> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: false);

    _rotationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration ?? const Duration(milliseconds: 300),
    );
    
    _rotationAnimation = Tween<double>(begin: widget.heading, end: widget.heading).animate(_rotationController);
  }

  double _shortestAngleDelta(double from, double to) {
    double delta = (to - from) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    return delta;
  }

  @override
  void didUpdateWidget(covariant GoogleNavigationMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.animationDuration != widget.animationDuration && widget.animationDuration != null) {
      _rotationController.duration = widget.animationDuration;
    }

    if (oldWidget.heading != widget.heading) {
      final currentAnimatedHeading = _rotationAnimation.value;
      final delta = _shortestAngleDelta(currentAnimatedHeading, widget.heading);
      final targetHeading = currentAnimatedHeading + delta;
      
      _rotationAnimation = Tween<double>(
        begin: currentAnimatedHeading,
        end: targetHeading,
      ).animate(CurvedAnimation(
        parent: _rotationController,
        curve: Curves.linear,
      ));
      
      _rotationController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // The marker has rotate: true in map_widget.dart, so it rotates WITH the map.
    // We only need to rotate the chevron by the vehicle's heading relative to North.

    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Pulsing halo ring (underneath)
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (_pulseController.value * 1.5),
                child: Opacity(
                  opacity: 1.0 - _pulseController.value,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.accentPrimary.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              );
            },
          ),
          
          // 2. Base accuracy circle (white)
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: Offset(0, 4), // Static shadow pointing DOWN on screen
                ),
              ],
            ),
          ),
          
          // 3. The rotated Chevron
          AnimatedBuilder(
            animation: _rotationAnimation,
            builder: (context, child) {
              final double angle = _rotationAnimation.value * (math.pi / 180.0);
              return Transform.rotate(
                angle: angle,
                child: CustomPaint(
                  size: const Size(28, 28),
                  painter: _ChevronPainter(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Define the chevron shape
    // Points: top center, bottom right, bottom center indent, bottom left
    final path = Path()
      ..moveTo(w / 2, 0) // Tip
      ..lineTo(w, h) // Bottom right
      ..lineTo(w / 2, h * 0.75) // Indent back
      ..lineTo(0, h) // Bottom left
      ..close();

    // 1. Draw crisp white border stroke
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeJoin = StrokeJoin.round;
    
    canvas.drawPath(path, borderPaint);

    // 2. Fill with rich blue gradient
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF4FC3F7), Color(0xFF1976D2)], // Bright to deep blue
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
