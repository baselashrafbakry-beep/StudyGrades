import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/admin_service.dart';
import '../services/storage_service.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'maintenance_screen.dart';

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
    if (kDebugMode) {
      debugPrint('[SPLASH] ====== SPLASH BOOTSTRAP START ======');
    }

    bool navigated = false;

    void navigateTo(Widget screen) {
      if (navigated || !mounted) return;
      navigated = true;
      if (kDebugMode) {
        debugPrint('[SPLASH] Navigating to ${screen.runtimeType}');
      }
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

    // ضمان عدم تجميد شاشة البدء (Safety timer 4 ثواني)
    Future.delayed(const Duration(milliseconds: 4000), () {
      if (!navigated && mounted) {
        if (kDebugMode) {
          debugPrint('[SPLASH] ⚠️ FALLBACK TRIGGERED - LoginScreen');
        }
        navigateTo(const LoginScreen());
      }
    });

    final auth = context.read<AuthProvider>();

    bool isAuth = false;
    try {
      await auth.restoreSession().timeout(const Duration(milliseconds: 2500));
      isAuth = auth.isAuthenticated;
    } catch (e) {
      if (kDebugMode) debugPrint('[SPLASH] ⚠️ Session restoration failed: $e');
      isAuth = false;
    }

    bool seenIntro = true;
    try {
      seenIntro = await StorageService.hasSeenIntro()
          .timeout(const Duration(milliseconds: 800));
    } catch (e) {
      if (kDebugMode) debugPrint('[SPLASH] ⚠️ Intro check failed: $e');
      seenIntro = true;
    }

    // حد أدنى لظهور شاشة البدء
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted || navigated) return;

    // فحص وضع الصيانة — يُستثنى منه المطور/المدير حتى يتمكنوا من
    // الدخول وإيقاف الصيانة من لوحة التحكم عند الحاجة
    bool maintenanceMode = false;
    try {
      maintenanceMode = await AdminService.getSystemSetting<bool>(
            'maintenance_mode',
            defaultValue: false,
          ).timeout(const Duration(milliseconds: 800)) ??
          false;
    } catch (e) {
      if (kDebugMode) debugPrint('[SPLASH] ⚠️ Maintenance check failed: $e');
    }

    final canBypassMaintenance =
        isAuth && (auth.user?.canEditSystemSettings ?? false);

    Widget nextScreen;
    if (maintenanceMode && !canBypassMaintenance) {
      nextScreen = const MaintenanceScreen();
    } else if (isAuth) {
      nextScreen = const HomeScreen();
    } else if (!seenIntro) {
      nextScreen = const OnboardingScreen();
    } else {
      nextScreen = const LoginScreen();
    }

    if (kDebugMode) {
      debugPrint('[SPLASH] → ${nextScreen.runtimeType}');
    }
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
    context.watch<
        ThemeProvider>(); // يضمن إعادة البناء فوراً عند تبديل الوضع الليلي/الفاتح
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
            ..._buildParticles(),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildAnimatedLogo(),
                  const SizedBox(height: 32),
                  FadeTransition(
                    opacity: _textFade,
                    child: SlideTransition(
                      position: _textSlide,
                      child: Column(
                        children: [
                          Text(
                            'Study Grades Voice',
                            style: GoogleFonts.cairo(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.0,
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
                  FadeTransition(
                    opacity: _textFade,
                    child: _buildLoadingDots(),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _textFade,
                child: Column(
                  children: [
                    Text(
                      'v${AdminService.appVersion}',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '© ${AdminService.copyrightYear} — ${AdminService.developerName} | ${AdminService.developerPhone}',
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
              ...List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _waveCtrl,
                  builder: (ctx, _) {
                    final progress = (_waveCtrl.value + (i * 0.33)) % 1.0;
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
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
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
