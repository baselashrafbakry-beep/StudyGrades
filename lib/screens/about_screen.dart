import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/admin_service.dart';
import '../theme/app_theme.dart';

/// شاشة "عن التطبيق" الاحترافية
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeIn,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    Fluttertoast.showToast(
      msg: 'تم نسخ $label ✅',
      backgroundColor: AppColors.success,
      textColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: CustomScrollView(
              slivers: [
                _buildSliverHeader(),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildAppInfoCard(),
                        const SizedBox(height: 16),
                        _buildDeveloperCard(),
                        const SizedBox(height: 16),
                        _buildFeaturesCard(),
                        const SizedBox(height: 16),
                        _buildTechCard(),
                        const SizedBox(height: 16),
                        _buildSubscriptionPlansCard(),
                        const SizedBox(height: 16),
                        _buildLegalCard(),
                        const SizedBox(height: 24),
                        _buildCopyrightFooter(),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliverHeader() {
    return SliverAppBar(
      expandedHeight: 220,
      floating: false,
      pinned: true,
      backgroundColor: AppColors.primary,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
        tooltip: 'رجوع',
      ),
      title: Text(
        'عن التطبيق',
        style: GoogleFonts.cairo(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A237E), Color(0xFF283593), Color(0xFF3949AB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 50),
              // أيقونة التطبيق في الـ header
              Hero(
                tag: 'appLogo',
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      'assets/icons/app_icon.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Icon(Icons.mic_rounded,
                            color: Colors.white, size: 50),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AdminService.appName,
                style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                AdminService.appNameAr,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppInfoCard() {
    return _Card(
      title: 'معلومات التطبيق',
      icon: Icons.info_outline_rounded,
      iconColor: AppColors.primary,
      children: [
        _infoRow('الإصدار', 'v${AdminService.appVersion}'),
        _infoRow('اسم الحزمة', AdminService.packageName),
        _infoRow('الإصدار المستهدف', 'Android 7.0+ / iOS 12+'),
        _infoRow('لغة البرمجة', 'Flutter (Dart)'),
        _infoRow('سنة الإصدار', AdminService.copyrightYear),
        _infoRow('رابط السيرفر', AdminService.serverUrl,
            copyValue: AdminService.serverUrlFull, copyLabel: 'رابط السيرفر'),
      ],
    );
  }

  Widget _buildDeveloperCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.engineering_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'المطور الرئيسي',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  Text(
                    AdminService.developerName,
                    style: GoogleFonts.cairo(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 14),
          // معلومات التواصل
          _devContactRow(
            icon: Icons.phone_in_talk_rounded,
            label: 'واتساب',
            value: AdminService.developerPhone,
            bgColor: const Color(0xFF25D366),
          ),
          const SizedBox(height: 10),
          _devContactRow(
            icon: Icons.email_rounded,
            label: 'البريد الإلكتروني',
            value: AdminService.developerEmail,
            bgColor: const Color(0xFFEA4335),
          ),
        ],
      ),
    );
  }

  Widget _devContactRow({
    required IconData icon,
    required String label,
    required String value,
    required Color bgColor,
  }) {
    return GestureDetector(
      onTap: () => _copyToClipboard(value, label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  const Icon(Icons.copy_rounded, size: 14, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesCard() {
    final features = [
      (Icons.mic_rounded, 'رصد الدرجات بالصوت', 'إدخال صوتي بالعربية المصرية'),
      (Icons.cloud_off_rounded, 'يعمل بدون إنترنت', 'أوفلاين + مزامنة تلقائية'),
      (Icons.analytics_rounded, 'تحليلات ذكية', 'رسوم بيانية + إحصائيات'),
      (Icons.file_download_rounded, 'تصدير متعدد', 'Excel + CSV'),
      (
        Icons.admin_panel_settings_rounded,
        'صلاحيات متعددة',
        '4 مستويات: مطور/مدير/مشرف/معلم'
      ),
      (Icons.sync_rounded, 'مزامنة تلقائية', 'offline-first architecture'),
      (Icons.security_rounded, 'تخزين آمن', 'JWT + تشفير محلي'),
      (Icons.school_rounded, 'إدارة شاملة', 'مراحل + فصول + مواد'),
    ];

    return _Card(
      title: 'مميزات التطبيق',
      icon: Icons.star_rounded,
      iconColor: AppColors.warning,
      children: features.map((f) => _featureRow(f.$1, f.$2, f.$3)).toList(),
    );
  }

  Widget _featureRow(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  desc,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle_outline_rounded,
              color: AppColors.success, size: 18),
        ],
      ),
    );
  }

  Widget _buildTechCard() {
    final tech = [
      ('Flutter 3.35.4', 'إطار العمل'),
      ('Dart 3.9.2', 'لغة البرمجة'),
      ('Django REST', 'الـ Backend'),
      ('Hive 2.2.3', 'قاعدة البيانات المحلية'),
      ('Provider 6.1.5', 'State Management'),
      ('Dio 5.8', 'HTTP Client'),
      ('speech_to_text 7.0', 'التعرف الصوتي'),
      ('fl_chart 0.69', 'الرسوم البيانية'),
    ];

    return _Card(
      title: 'التقنيات المستخدمة',
      icon: Icons.code_rounded,
      iconColor: AppColors.info,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tech.map((t) => _techChip(t.$1, t.$2)).toList(),
        ),
      ],
    );
  }

  Widget _techChip(String name, String role) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.info,
            ),
          ),
          Text(
            role,
            style: GoogleFonts.cairo(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionPlansCard() {
    final plans = [
      ('مجاني', '0 جنيه', '1 معلم · 30 طالب · 2 فصل', AppColors.success),
      ('أساسي', '49 جنيه/شهر', '50 طالب · 5 فصول · أوفلاين', AppColors.info),
      (
        'احترافي',
        '99 جنيه/شهر',
        'غير محدود · Excel · دعم أولوية',
        AppColors.warning
      ),
      (
        'مؤسسي',
        '2999 جنيه/سنة',
        'كل المدرسة · لوحة إدارة كاملة',
        AppColors.primary
      ),
    ];

    return _Card(
      title: 'خطط الاشتراك',
      icon: Icons.workspace_premium_rounded,
      iconColor: AppColors.warning,
      children: plans
          .map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: p.$4.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.$4.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: p.$4.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.workspace_premium_rounded,
                          color: p.$4,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.$1,
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              p.$3,
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        p.$2,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: p.$4,
                        ),
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildLegalCard() {
    return _Card(
      title: 'القانونية والخصوصية',
      icon: Icons.gavel_rounded,
      iconColor: Colors.grey.shade600,
      children: [
        _legalRow(
          Icons.privacy_tip_outlined,
          'سياسة الخصوصية',
          'لا نشارك بياناتك مع أي طرف ثالث.',
        ),
        _legalRow(
          Icons.storage_rounded,
          'تخزين البيانات',
          'جميع بياناتك تُحفظ على جهازك أو السيرفر الخاص بك.',
        ),
        _legalRow(
          Icons.copyright_rounded,
          'حقوق الملكية',
          'جميع الحقوق محفوظة © ${AdminService.copyrightYear} ${AdminService.developerName}',
        ),
        _legalRow(
          Icons.update_rounded,
          'التحديثات',
          'التطبيق يُحدَّث دورياً بميزات جديدة.',
        ),
      ],
    );
  }

  Widget _legalRow(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey.shade500, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  desc,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyrightFooter() {
    return Column(
      children: [
        Container(
          height: 4,
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${AdminService.appName} v${AdminService.appVersion}',
          style: GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '© ${AdminService.copyrightYear} — تطوير ${AdminService.developerName}',
          style: GoogleFonts.cairo(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'جميع الحقوق محفوظة — صُنع في مصر 🇪🇬',
          style: GoogleFonts.cairo(
            fontSize: 11,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    String? copyValue,
    String? copyLabel,
  }) {
    return GestureDetector(
      onTap: copyValue != null
          ? () => _copyToClipboard(copyValue, copyLabel ?? label)
          : null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                value,
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.start,
              ),
            ),
            if (copyValue != null)
              const Icon(Icons.copy_rounded,
                  size: 14, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

/// بطاقة موحدة القالب
class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  const _Card({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
