import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../core/app_colors.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Redesigned Splash Screen with Fluid Choreography
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _pulseController;
  
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<Offset> _logoSlide;
  
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _blurAnimation;
  
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    
    // Main choreography controller
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    );

    // Subtle breathing pulse for the glow
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _setupAnimations();
    _controller.forward();
    _initializeApp();
  }

  void _setupAnimations() {
    // Logo drops in from above, scales down and snaps into place
    _logoSlide = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: const Offset(0, -0.5), end: const Offset(0, 0.1)).chain(CurveTween(curve: Curves.easeOutBack)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: const Offset(0, 0.1), end: const Offset(0, 0)).chain(CurveTween(curve: Curves.easeInOut)), weight: 60),
    ]).animate(_controller);

    _logoScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.1).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 60),
    ]).animate(_controller);

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4, curve: Curves.easeIn)),
    );

    // Text slides up and fades in after logo
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 0.8, curve: Curves.easeOutCubic)),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 0.9, curve: Curves.easeIn)),
    );

    // Background blur resolves over time for a cinematic reveal
    _blurAnimation = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.8, curve: Curves.easeOut)),
    );
  }

  Future<void> _initializeApp() async {
    // Wait for the exact moment the animation feels complete
    await Future.delayed(const Duration(milliseconds: 2800));

    if (!mounted) return;
    
    try {
      final AppUpdateInfo updateInfo = await InAppUpdate.checkForUpdate();
      if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
        if (updateInfo.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
        } else if (updateInfo.flexibleUpdateAllowed) {
          await InAppUpdate.startFlexibleUpdate();
          await InAppUpdate.completeFlexibleUpdate();
        }
      }
    } catch (e) {
      debugPrint("Failed to check for updates: $e");
    }

    if (!mounted) return;
    final authProvider = context.read<AuthProvider>();
    await authProvider.initialize();

    if (!mounted) return;
    
    setState(() { _isNavigating = true; });
    
    // Smooth fade out of the splash screen
    await _controller.reverse(from: 1.0);
    
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

    if (!hasSeenOnboarding) {
      Navigator.of(context).pushReplacementNamed('/onboarding');
    } else if (authProvider.isLoggedIn) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: colors.primaryBackground,
      body: AnimatedBuilder(
        animation: Listenable.merge([_controller, _pulseController]),
        builder: (context, child) {
          // A rich cinematic background mask
          return Stack(
            fit: StackFit.expand,
            children: [
              // Dynamic Background Gradient
              Container(
                decoration: BoxDecoration(gradient: colors.primaryGradient),
              ),
              
              // Animated Blur Overlay
              if (_blurAnimation.value > 0)
                BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: _blurAnimation.value,
                    sigmaY: _blurAnimation.value,
                  ),
                  child: Container(color: Colors.transparent),
                ),

              // Main Content
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated Logo
                    SlideTransition(
                      position: _logoSlide,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: FadeTransition(
                          opacity: _logoOpacity,
                          child: _buildLogoContainer(colors),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Animated Typography
                    SlideTransition(
                      position: _textSlide,
                      child: FadeTransition(
                        opacity: _textOpacity,
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            Text(
                              '',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colors.textSecondary,
                                letterSpacing: 4,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Subtle Loading Indicator at the bottom
              Positioned(
                bottom: 48,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: (_textOpacity.value > 0.8 && !_isNavigating) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colors.accentPrimary.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLogoContainer(AppColorScheme colors) {
    // Creating a premium glowing effect behind the transparent logo
    final glowOpacity = 0.2 + (0.15 * _pulseController.value);
    
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: colors.accentPrimary.withValues(alpha: glowOpacity),
            blurRadius: 70,
            spreadRadius: 20 * _pulseController.value,
          ),
          BoxShadow(
            color: colors.accentSecondary.withValues(alpha: glowOpacity),
            blurRadius: 60,
            spreadRadius: -5,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Image.asset(
          'assets/logo_transparent.png',
          height: 220,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
