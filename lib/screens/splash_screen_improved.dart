import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoCtrl;
  late AnimationController _waveCtrl;
  late AnimationController _textCtrl;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _logoScale = CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut);
    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeIn);
    _textFade = CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn);
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOutCubic));

    _logoCtrl.forward();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _textCtrl.forward();
    });

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    print('[SPLASH] ========== SPLASH BOOTSTRAP START ==========');
    print('[SPLASH] Timestamp: ${DateTime.now()}');
    
    // HARD safety timer: navigate to LoginScreen no matter what after 4s.
    bool navigated = false;
    void navigateTo(Widget screen) {
      if (navigated || !mounted) {
        print('[SPLASH] Navigation skipped - already navigated or unmounted');
        return;
      }
      navigated = true;
      print('[SPLASH] Navigating to ${screen.runtimeType}');
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: screen,
          ),
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    }

    // Fallback timer — guarantees the user never sees a frozen splash.
    print('[SPLASH] Setting 4-second fallback timer...');
    Future.delayed(const Duration(milliseconds: 4000), () {
      if (!navigated && mounted) {
        print('[SPLASH] ⚠️ FALLBACK TRIGGERED - Navigating to LoginScreen');
        navigateTo(const LoginScreen());
      }
    });

    final auth = context.read<AuthProvider>();
    print('[SPLASH] AuthProvider obtained');

    // Each step gets its own timeout so a single hang can never block boot.
    bool isAuth = false;
    try {
      print('[SPLASH] Attempting to restore session...');
      await auth
          .restoreSession()
          .timeout(const Duration(milliseconds: 2500));
      isAuth = auth.isAuthenticated;
      print('[SPLASH] ✓ Session restored. isAuth: $isAuth');
    } catch (e) {
      print('[SPLASH] ⚠️ Session restoration failed: $e');
      isAuth = false;
    }

    bool seenIntro = true; // default to skipping onboarding on failure
    try {
      print('[SPLASH] Checking if intro was seen...');
      seenIntro = await StorageService.hasSeenIntro()
          .timeout(const Duration(milliseconds: 800));
      print('[SPLASH] ✓ Intro check completed. seenIntro: $seenIntro');
    } catch (e) {
      print('[SPLASH] ⚠️ Failed to check intro status: $e');
      seenIntro = true;
    }

    // Minimum splash visibility for branding (only if we still have time).
    print('[SPLASH] Waiting for minimum splash visibility (1500ms)...');
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted || navigated) {
      print('[SPLASH] ⚠️ Bootstrap cancelled - not mounted or already navigated');
      return;
    }

    Widget nextScreen;
    if (isAuth) {
      nextScreen = const HomeScreen();
      print('[SPLASH] Selected screen: HomeScreen (authenticated)');
    } else if (!seenIntro) {
      nextScreen = const OnboardingScreen();
      print('[SPLASH] Selected screen: OnboardingScreen (first time)');
    } else {
      nextScreen = const LoginScreen();
      print('[SPLASH] Selected screen: LoginScreen (not authenticated)');
    }

    print('[SPLASH] ========== SPLASH BOOTSTRAP END ==========');
    navigateTo(nextScreen);
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _waveCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0D47A1),
              Color(0xFF1565C0),
              Color(0xFF1976D2),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Background floating particles
            ..._buildParticles(),
            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated logo with sound waves
                  _buildAnimatedLogo(),
                  const SizedBox(height: 32),
                  // Animated app name
                  FadeTransition(
                    opacity: _textFade,
                    child: SlideTransition(
                      position: _textSlide,
                      child: Column(
                        children: [
                          Text(
                            'StudyGrades 2026',
                            style: GoogleFonts.cairo(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.2,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              '🎤 نظام رصد الدرجات الصوتي',
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 60),
                  // Loading indicator with dots
                  FadeTransition(
                    opacity: _textFade,
                    child: _buildLoadingDots(),
                  ),
                ],
              ),
            ),
            // Bottom version info
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _textFade,
                child: Column(
                  children: [
                    Text(
                      'v1.0.0',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '© 2026 — للمعلم باسل أشرف',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedLogo() {
    return FadeTransition(
      opacity: _logoFade,
      child: ScaleTransition(
        scale: _logoScale,
        child: SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulsating sound waves
              ...List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _waveCtrl,
                  builder: (ctx, _) {
                    final progress =
                        (_waveCtrl.value + (i * 0.33)) % 1.0;
                    final size = 130 + (progress * 90);
                    final opacity = (1.0 - progress).clamp(0.0, 1.0);
                    return Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: opacity * 0.6),
                          width: 2,
                        ),
                      ),
                    );
                  },
                );
              }),
              // Center logo container
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.4),
                      blurRadius: 40,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.mic_rounded,
                      size: 78,
                      color: AppColors.primary,
                    ),
                    Positioned(
                      bottom: 18,
                      child: Icon(
                        Icons.school_rounded,
                        size: 22,
                        color: AppColors.primary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingDots() {
    return AnimatedBuilder(
      animation: _waveCtrl,
      builder: (ctx, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final t = (_waveCtrl.value + (i * 0.2)) % 1.0;
            final scale = 0.6 + (math.sin(t * math.pi * 2) * 0.5 + 0.5) * 0.5;
            return Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Transform.scale(
                scale: scale.clamp(0.6, 1.1),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.3 + scale * 0.5),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  List<Widget> _buildParticles() {
    final random = math.Random(42);
    return List.generate(15, (i) {
      final x = random.nextDouble();
      final y = random.nextDouble();
      final size = 4.0 + random.nextDouble() * 8;
      final delay = random.nextDouble();

      return Positioned(
        left: x * MediaQuery.of(context).size.width,
        top: y * MediaQuery.of(context).size.height,
        child: AnimatedBuilder(
          animation: _waveCtrl,
          builder: (ctx, _) {
            final t = (_waveCtrl.value + delay) % 1.0;
            final opacity = (math.sin(t * math.pi * 2) * 0.5 + 0.5) * 0.3;
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: opacity),
              ),
            );
          },
        ),
      );
    });
  }
}
