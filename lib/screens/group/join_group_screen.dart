import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../core/app_colors.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> with TickerProviderStateMixin {
  final _codeController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isJoining = false;
  
  late AnimationController _enterAnimController;
  late AnimationController _floatAnimController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _enterAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    _floatAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _enterAnimController, curve: Curves.easeOutExpo),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _enterAnimController, curve: Curves.easeOutExpo),
    );
    
    _enterAnimController.forward();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _focusNode.dispose();
    _enterAnimController.dispose();
    _floatAnimController.dispose();
    super.dispose();
  }

  void _startQRScan() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Color(0xFF14171A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: MobileScanner(
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final String code = barcodes.first.rawValue ?? '';
                      if (code.length >= 6) {
                        Navigator.pop(context);
                        _codeController.text = code.substring(0, 6);
                        _handleJoin();
                      }
                    }
                  },
                ),
              ),
              Positioned(
                top: 24,
                left: 24,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF26DE81), width: 4),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
              const Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Text(
                  'Scan Trip QR Code',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleJoin() async {
    final code = _codeController.text.trim();
    if (code.length < 6) return;

    FocusScope.of(context).unfocus();
    setState(() => _isJoining = true);

    try {
      final groupProvider = context.read<GroupProvider>();
      groupProvider.setToken(context.read<AuthProvider>().token);

      final group = await groupProvider.joinGroup(code);

      if (group != null && mounted) {
        Navigator.of(context).pushReplacementNamed('/group-lobby', arguments: group.id);
      }
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  Widget _buildSegment(String char, bool isActive) {
    final hasChar = char.isNotEmpty;
    final Color activeColor = const Color(0xFF26DE81);
    final Color defaultColor = const Color(0xFF1E2228);
    final Color defaultBorderColor = const Color(0xFF2C3138);

    return Container(
      width: 44,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: defaultColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? activeColor : defaultBorderColor,
          width: isActive ? 1.5 : 1.0,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: activeColor.withValues(alpha: 0.2),
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ]
            : [],
      ),
      alignment: Alignment.center,
      child: isActive && !hasChar
          ? Container(
              width: 2,
              height: 24,
              color: activeColor,
            )
          : Text(
              char,
              style: const TextStyle(
                fontSize: 24,
                fontFamily: 'Monospace',
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = const Color(0xFF111417);
    final Color primaryGreen = const Color(0xFF26DE81);
    final Color secondaryGreen = const Color(0xFF1CB767);
    final Color surfaceColor = const Color(0xFF1E2228);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: surfaceColor.withValues(alpha: 0.5),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  
                  // Top Icon
                  AnimatedBuilder(
                    animation: _floatAnimController,
                    builder: (context, child) {
                      return Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: primaryGreen.withValues(alpha: 0.05),
                          border: Border.all(color: primaryGreen.withValues(alpha: 0.1), width: 1),
                        ),
                        child: Center(
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  primaryGreen.withValues(alpha: 0.2),
                                  Colors.transparent,
                                ],
                              ),
                              border: Border.all(color: primaryGreen.withValues(alpha: 0.3), width: 2),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Transform.rotate(
                                  angle: _floatAnimController.value * 2 * math.pi,
                                  child: Container(
                                    width: 70,
                                    height: 70,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: primaryGreen, width: 2, style: BorderStyle.none),
                                    ),
                                    child: CustomPaint(
                                      painter: DashedCirclePainter(color: primaryGreen),
                                    ),
                                  ),
                                ),
                                Icon(Icons.location_on_rounded, size: 36, color: primaryGreen),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Title
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                      children: [
                        const TextSpan(text: 'Join ', style: TextStyle(color: Colors.white)),
                        TextSpan(text: 'Trip', style: TextStyle(color: primaryGreen)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Subtitle
                  Text(
                    'Enter the 6-character party code\nshared by your trip leader.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: 0.6),
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  // Code Input Container
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: primaryGreen.withValues(alpha: 0.2)),
                    ),
                    child: Builder(
                      builder: (BuildContext context) {
                        Offset? tapPosition;
                        return GestureDetector(
                          onTapDown: (details) => tapPosition = details.globalPosition,
                          onTap: () => FocusScope.of(context).requestFocus(_focusNode),
                          onLongPress: () async {
                            if (tapPosition == null) return;
                            final result = await showMenu<String>(
                              context: context,
                              color: const Color(0xFF2C3138),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              position: RelativeRect.fromLTRB(
                                tapPosition!.dx, 
                                tapPosition!.dy - 60, 
                                tapPosition!.dx, 
                                tapPosition!.dy,
                              ),
                              items: [
                                const PopupMenuItem(
                                  value: 'paste',
                                  height: 40,
                                  child: Row(
                                    children: [
                                      Icon(Icons.content_paste_rounded, color: Colors.white, size: 20),
                                      SizedBox(width: 12),
                                      Text('Paste', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ],
                            );
                            
                            if (result == 'paste') {
                              final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
                              if (clipboardData != null && clipboardData.text != null) {
                                final text = clipboardData.text!.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
                                if (text.isNotEmpty) {
                                  setState(() {
                                    _codeController.text = text.substring(0, text.length > 6 ? 6 : text.length);
                                  });
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Pasted from clipboard', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                        backgroundColor: Color(0xFF26DE81),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                  if (_codeController.text.length == 6) {
                                    _handleJoin();
                                  }
                                }
                              }
                            }
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(
                                opacity: 0,
                                child: TextField(
                                  focusNode: _focusNode,
                                  controller: _codeController,
                                  keyboardType: TextInputType.text,
                                  textCapitalization: TextCapitalization.characters,
                                  maxLength: 6,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                                  ],
                                  onChanged: (val) {
                                    setState(() {});
                                    if (val.length == 6) {
                                      _handleJoin();
                                    }
                                  },
                                ),
                              ),
                              
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(6, (index) {
                                    final text = _codeController.text;
                                    final char = index < text.length ? text[index].toUpperCase() : '';
                                    final isActive = index == text.length || (index == 5 && text.length == 6);
                                    return _buildSegment(char, isActive && _focusNode.hasFocus);
                                  }),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Error Message
                  Consumer<GroupProvider>(
                    builder: (context, gp, _) {
                      if (gp.errorMessage != null) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B1010).withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFEF9A9A).withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: Color(0xFFFF8A80), size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    gp.errorMessage!,
                                    style: const TextStyle(color: Color(0xFFFFCDD2), fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }
                  ),

                  // Join Button
                  Container(
                    height: 60,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: LinearGradient(
                        colors: _codeController.text.length == 6
                            ? [primaryGreen, secondaryGreen]
                            : [surfaceColor, surfaceColor],
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: (_isJoining || _codeController.text.length < 6) ? null : _handleJoin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: _isJoining
                          ? const SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                            )
                          : Stack(
                              alignment: Alignment.center,
                              children: [
                                Align(
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Join Trip',
                                    style: TextStyle(
                                      fontSize: 18, 
                                      fontWeight: FontWeight.bold, 
                                      color: _codeController.text.length == 6 ? Colors.white : Colors.white54,
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black.withValues(alpha: 0.2),
                                    ),
                                    child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                                  ),
                                )
                              ],
                            ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // OR Divider
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.1))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.1))),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Scan QR Button
                  Container(
                    height: 60,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: InkWell(
                      onTap: _startQRScan,
                      borderRadius: BorderRadius.circular(30),
                      child: Row(
                        children: [
                          const SizedBox(width: 24),
                          Icon(Icons.qr_code_scanner_rounded, color: primaryGreen, size: 24),
                          const SizedBox(width: 16),
                          Container(
                            width: 1,
                            height: 24,
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Text(
                              'Scan QR Code',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 24),
                          const SizedBox(width: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashedCirclePainter extends CustomPainter {
  final Color color;

  DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    const dashWidth = 8.0;
    const dashSpace = 6.0;
    
    double circumference = 2 * math.pi * radius;
    int dashCount = (circumference / (dashWidth + dashSpace)).floor();
    
    double sweepAngle = (dashWidth / circumference) * 2 * math.pi;
    double spaceAngle = (dashSpace / circumference) * 2 * math.pi;
    
    double startAngle = 0.0;
    
    for (int i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle + spaceAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
