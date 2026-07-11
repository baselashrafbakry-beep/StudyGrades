import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// شاشات الترحيب للمستخدمين الجدد - Onboarding
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  final List<_OnboardingPage> _pages = const [
    _OnboardingPage(
      icon: Icons.mic_rounded,
      title: 'رصد الدرجات بالصوت',
      description:
          'سجل درجات طلابك بسهولة عبر الإدخال الصوتي بالعربية المصرية. وفر وقتك وجهدك.',
      color: AppColors.primary,
      gradient: AppColors.primaryGradient,
    ),
    _OnboardingPage(
      icon: Icons.cloud_off_rounded,
      title: 'يعمل أوفلاين',
      description:
          'سجل الدرجات بدون إنترنت، وستتم مزامنتها تلقائياً عند توفر الاتصال.',
      color: AppColors.success,
      gradient: AppColors.successGradient,
    ),
    _OnboardingPage(
      icon: Icons.analytics_rounded,
      title: 'تحليلات ذكية',
      description:
          'احصل على رسوم بيانية تفاعلية، إحصائيات شاملة، وتحليل أداء الطلاب لحظياً.',
      color: AppColors.info,
      gradient: LinearGradient(
        colors: [Color(0xFF29B6F6), Color(0xFF0277BD)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    _OnboardingPage(
      icon: Icons.share_rounded,
      title: 'تصدير ومشاركة',
      description:
          'صدّر الدرجات بصيغة Excel أو PDF، وشاركها بسهولة مع أولياء الأمور أو الإدارة.',
      color: AppColors.warning,
      gradient: LinearGradient(
        colors: [Color(0xFFFFA726), Color(0xFFEF6C00)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
  ];

  Future<void> _finish() async {
    await StorageService.markIntroSeen();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _finish,
                    child: Text(
                      'تخطي',
                      style: GoogleFonts.cairo(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '${_currentPage + 1} / ${_pages.length}',
                      style: GoogleFonts.cairo(
                        color: AppColors.textHint,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, i) => _buildPage(_pages[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SmoothPageIndicator(
                controller: _controller,
                count: _pages.length,
                effect: ExpandingDotsEffect(
                  activeDotColor: _pages[_currentPage].color,
                  dotColor: Colors.grey.shade300,
                  dotHeight: 8,
                  dotWidth: 8,
                  expansionFactor: 4,
                  spacing: 6,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _controller.previousPage(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: _pages[_currentPage].color),
                          foregroundColor: _pages[_currentPage].color,
                        ),
                        child: Text(
                          'السابق',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  if (_currentPage > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _next,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pages[_currentPage].color,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _currentPage == _pages.length - 1
                                ? 'ابدأ الآن'
                                : 'التالي',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            _currentPage == _pages.length - 1
                                ? Icons.rocket_launch_rounded
                                : Icons.arrow_back_rounded,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 700),
            tween: Tween(begin: 0.5, end: 1.0),
            curve: Curves.elasticOut,
            builder: (_, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                gradient: page.gradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: page.color.withValues(alpha: 0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(page.icon, size: 110, color: Colors.white),
            ),
          ),
          const SizedBox(height: 50),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 15,
              height: 1.7,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final Gradient gradient;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.gradient,
  });
}
