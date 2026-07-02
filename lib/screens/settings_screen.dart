import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../providers/auth_provider.dart';
import '../providers/grading_provider.dart';
import '../providers/theme_provider.dart';
import '../services/admin_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'activity_log_screen.dart';
import 'admin/admin_panel_screen.dart';
import 'subscription_screen.dart';
import 'about_screen.dart';
import 'activate_subscription_screen.dart';

/// شاشة الإعدادات والتخصيصات
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoSync = true;
  bool _hapticFeedback = true;
  bool _showStudentNumbers = true;
  bool _useServerSpeech = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _autoSync = StorageService.getSetting<bool>(
            'auto_sync',
            defaultValue: true,
          ) ??
          true;
      _hapticFeedback = StorageService.getSetting<bool>(
            'haptic_feedback',
            defaultValue: true,
          ) ??
          true;
      _showStudentNumbers = StorageService.getSetting<bool>(
            'show_student_numbers',
            defaultValue: true,
          ) ??
          true;
      _useServerSpeech = StorageService.getSetting<bool>(
            'use_server_speech',
            defaultValue: false,
          ) ??
          false;
    });
  }

  Future<void> _setSetting(String key, dynamic value) async {
    await StorageService.setSetting(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final grading = context.watch<GradingProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
                children: [
                  _buildProfileCard(auth),
                  const SizedBox(height: 16),
                  _sectionTitle('عام', Icons.tune_rounded),
                  _settingTile(
                    icon: Icons.cloud_sync_rounded,
                    iconColor: AppColors.primary,
                    title: 'المزامنة التلقائية',
                    subtitle: 'مزامنة الدرجات تلقائياً عند توفر الإنترنت',
                    trailing: Switch(
                      value: _autoSync,
                      activeThumbColor: AppColors.primary,
                      onChanged: (v) {
                        setState(() => _autoSync = v);
                        _setSetting('auto_sync', v);
                      },
                    ),
                  ),
                  _settingTile(
                    icon: Icons.vibration_rounded,
                    iconColor: AppColors.info,
                    title: 'الاهتزاز التفاعلي',
                    subtitle: 'اهتزاز الجهاز عند العمليات المهمة',
                    trailing: Switch(
                      value: _hapticFeedback,
                      activeThumbColor: AppColors.primary,
                      onChanged: (v) {
                        setState(() => _hapticFeedback = v);
                        _setSetting('haptic_feedback', v);
                      },
                    ),
                  ),
                  _settingTile(
                    icon: Icons.numbers_rounded,
                    iconColor: AppColors.warning,
                    title: 'عرض رقم الجلوس',
                    subtitle: 'إظهار رقم جلوس الطالب في القوائم',
                    trailing: Switch(
                      value: _showStudentNumbers,
                      activeThumbColor: AppColors.primary,
                      onChanged: (v) {
                        setState(() => _showStudentNumbers = v);
                        _setSetting('show_student_numbers', v);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle('المظهر', Icons.palette_rounded),
                  _buildThemeTile(),
                  const SizedBox(height: 16),
                  _sectionTitle('الإدخال الصوتي', Icons.mic_rounded),
                  _settingTile(
                    icon: Icons.cloud_outlined,
                    iconColor: AppColors.success,
                    title: 'استخدام Whisper AI',
                    subtitle: _useServerSpeech
                        ? 'دقة عالية - يحتاج إنترنت'
                        : 'سريع - يعمل أوفلاين',
                    trailing: Switch(
                      value: _useServerSpeech,
                      activeThumbColor: AppColors.primary,
                      onChanged: (v) {
                        setState(() => _useServerSpeech = v);
                        _setSetting('use_server_speech', v);
                      },
                    ),
                  ),
                  _settingTile(
                    icon: Icons.language_rounded,
                    iconColor: AppColors.primary,
                    title: 'لغة التعرف',
                    subtitle: 'العربية المصرية',
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: AppColors.textHint,
                    ),
                    onTap: () => _showLanguageDialog(),
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle('البيانات والمزامنة', Icons.storage_rounded),
                  _settingTile(
                    icon: Icons.history_rounded,
                    iconColor: AppColors.info,
                    title: 'سجل النشاطات',
                    subtitle: 'عرض سجل المزامنات والعمليات',
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: AppColors.textHint,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ActivityLogScreen(),
                        ),
                      );
                    },
                  ),
                  _settingTile(
                    icon: Icons.cloud_upload_rounded,
                    iconColor: AppColors.warning,
                    title: 'مزامنة يدوية',
                    subtitle: grading.pendingCount > 0
                        ? '${grading.pendingCount} عنصر بانتظار المزامنة'
                        : 'كل البيانات متزامنة',
                    trailing: grading.isSyncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: AppColors.textHint,
                          ),
                    onTap: () => _manualSync(grading),
                  ),
                  _settingTile(
                    icon: Icons.delete_sweep_rounded,
                    iconColor: AppColors.error,
                    title: 'مسح البيانات المخزنة',
                    subtitle: 'حذف الكاش والإعدادات المحلية',
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: AppColors.textHint,
                    ),
                    onTap: () => _confirmClearCache(),
                  ),
                  if (auth.user?.canAccessAdminPanel ?? false) ...[
                    const SizedBox(height: 16),
                    _sectionTitle(
                        'لوحة تحكم المطوّر', Icons.admin_panel_settings_rounded),
                    _buildAdminPanelTile(),
                  ],
                  const SizedBox(height: 16),
                  _sectionTitle('الاشتراك', Icons.star_rounded),
                  _settingTile(
                    icon: Icons.workspace_premium_rounded,
                    iconColor: const Color(0xFF7B1FA2),
                    title: 'خطط الاشتراك',
                    subtitle: 'عرض الخطط والأسعار للترقية',
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B1FA2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'ترقية',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle('عن التطبيق', Icons.info_outline_rounded),
                  _settingTile(
                    icon: Icons.info_rounded,
                    iconColor: AppColors.primary,
                    title: 'إصدار التطبيق',
                    subtitle: '${AdminService.appNameAr} v${AdminService.appVersion}',
                  ),
                  _settingTile(
                    icon: Icons.person_rounded,
                    iconColor: AppColors.info,
                    title: 'المطور',
                    subtitle: AdminService.developerName,
                    trailing: const Icon(Icons.arrow_forward_ios_rounded,
                        size: 16, color: AppColors.textHint),
                    onTap: () => _showDeveloperInfo(),
                  ),
                  _settingTile(
                    icon: Icons.phone_rounded,
                    iconColor: AppColors.success,
                    title: 'واتساب للدعم',
                    subtitle: AdminService.developerPhone,
                    trailing: const Icon(Icons.copy_rounded,
                        size: 16, color: AppColors.textHint),
                    onTap: () {
                      Clipboard.setData(
                          const ClipboardData(text: AdminService.developerPhone));
                      Fluttertoast.showToast(
                        msg: 'تم نسخ رقم الواتساب',
                        backgroundColor: AppColors.success,
                        textColor: Colors.white,
                      );
                    },
                  ),
                  _settingTile(
                    icon: Icons.email_rounded,
                    iconColor: AppColors.warning,
                    title: 'البريد الإلكتروني',
                    subtitle: AdminService.developerEmail,
                    trailing: const Icon(Icons.copy_rounded,
                        size: 16, color: AppColors.textHint),
                    onTap: () {
                      Clipboard.setData(
                          const ClipboardData(text: AdminService.developerEmail));
                      Fluttertoast.showToast(
                        msg: 'تم نسخ البريد الإلكتروني',
                        backgroundColor: AppColors.success,
                        textColor: Colors.white,
                      );
                    },
                  ),
                  _settingTile(
                    icon: Icons.help_outline_rounded,
                    iconColor: AppColors.info,
                    title: 'المساعدة والدعم',
                    subtitle: 'تعليمات استخدام التطبيق',
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: AppColors.textHint,
                    ),
                    onTap: () => _showHelpDialog(),
                  ),
                  _settingTile(
                    icon: Icons.info_outline_rounded,
                    iconColor: AppColors.primary,
                    title: 'عن التطبيق',
                    subtitle: 'المعلومات التقنية والقانونية',
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: AppColors.textHint,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    ),
                  ),
                  _settingTile(
                    icon: Icons.key_rounded,
                    iconColor: AppColors.warning,
                    title: 'تفعيل رمز اشتراك',
                    subtitle: 'أدخل رمز التفعيل للترقية',
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'تفعيل',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: AppColors.warning,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ActivateSubscriptionScreen()),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _logoutButton(),
                  const SizedBox(height: 18),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          AdminService.appNameAr,
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          'v${AdminService.appVersion} — تطوير: ${AdminService.developerName}',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: AppColors.textHint,
                          ),
                        ),
                        Text(
                          '© ${AdminService.copyrightYear} — جميع الحقوق محفوظة',
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Text(
              'الإعدادات',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildProfileCard(AuthProvider auth) {
    final user = auth.user;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppColors.primary,
              size: 36,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  user?.username ?? 'المعلم',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email.isNotEmpty ?? false
                      ? user!.email
                      : 'حساب معلم',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _roleIcon(user?.role),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _roleLabel(user?.role),
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminPanelTile() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6A1B9A), Color(0xFF1A237E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6A1B9A).withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Color(0xFF6A1B9A),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'لوحة تحكم المطوّر',
                      style: GoogleFonts.cairo(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'إدارة المستخدمين • الإحصاءات • إعدادات النظام',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_back_ios_rounded,
                color: Colors.white,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeTile() {
    final themeProvider = context.watch<ThemeProvider>();
    final mode = themeProvider.themeMode;
    String subtitle;
    IconData icon;
    Color iconColor;
    switch (mode) {
      case ThemeMode.dark:
        subtitle = 'الوضع الداكن مفعّل - مريح للعين';
        icon = Icons.dark_mode_rounded;
        iconColor = const Color(0xFF5C6BC0);
        break;
      case ThemeMode.light:
        subtitle = 'الوضع الفاتح مفعّل - الافتراضي';
        icon = Icons.light_mode_rounded;
        iconColor = AppColors.warning;
        break;
      case ThemeMode.system:
        subtitle = 'يتبع إعدادات النظام تلقائياً';
        icon = Icons.brightness_auto_rounded;
        iconColor = AppColors.info;
        break;
    }
    return _settingTile(
      icon: icon,
      iconColor: iconColor,
      title: 'وضع المظهر',
      subtitle: subtitle,
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 16,
        color: AppColors.textHint,
      ),
      onTap: _showThemeDialog,
    );
  }

  void _showThemeDialog() {
    final themeProvider = context.read<ThemeProvider>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.palette_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'اختر وضع المظهر',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _themeOption(
              ctx,
              themeProvider,
              ThemeMode.light,
              'الوضع الفاتح',
              'مناسب للقراءة في الإضاءة الجيدة',
              Icons.light_mode_rounded,
              AppColors.warning,
            ),
            _themeOption(
              ctx,
              themeProvider,
              ThemeMode.dark,
              'الوضع الداكن',
              'مريح للعين في الإضاءة الخافتة',
              Icons.dark_mode_rounded,
              const Color(0xFF5C6BC0),
            ),
            _themeOption(
              ctx,
              themeProvider,
              ThemeMode.system,
              'تلقائي (نظام التشغيل)',
              'يتبع إعدادات النظام تلقائياً',
              Icons.brightness_auto_rounded,
              AppColors.info,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إغلاق', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _themeOption(
    BuildContext ctx,
    ThemeProvider provider,
    ThemeMode mode,
    String title,
    String subtitle,
    IconData icon,
    Color iconColor,
  ) {
    final selected = provider.themeMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await provider.setTheme(mode);
        if (ctx.mounted) Navigator.pop(ctx);
        Fluttertoast.showToast(
          msg: 'تم تغيير المظهر بنجاح',
          backgroundColor: AppColors.success,
          textColor: Colors.white,
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : Colors.grey.withValues(alpha: 0.2),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
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
                    subtitle,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppColors.success, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _logoutButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _confirmLogout,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.error,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: const Icon(Icons.logout_rounded),
        label: Text(
          'تسجيل الخروج',
          style: GoogleFonts.cairo(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'لغة التعرف الصوتي',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _langOption('العربية المصرية', 'ar_EG', true),
            _langOption('العربية الفصحى', 'ar_SA', false),
            _langOption('العربية المغربية', 'ar_MA', false),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إغلاق', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  // دوال مساعدة لعرض الدور بشكل صحيح لجميع الأدوار الأربعة
  String _roleLabel(String? role) {
    switch (role) {
      case 'developer': return 'مطوّر';
      case 'admin':     return 'مدير';
      case 'manager':   return 'مشرف';
      default:          return 'معلم';
    }
  }

  String _roleIcon(String? role) {
    switch (role) {
      case 'developer': return '👨‍💻';
      case 'admin':     return '🛡️';
      case 'manager':   return '🎓';
      default:          return '📚';
    }
  }

  Widget _langOption(String name, String code, bool selected) {
    return ListTile(
      title: Text(name, style: GoogleFonts.cairo()),
      trailing: selected
          ? const Icon(Icons.check_circle, color: AppColors.success)
          : null,
      onTap: () => Navigator.pop(context),
    );
  }

  Future<void> _manualSync(GradingProvider grading) async {
    if (grading.pendingCount == 0) {
      Fluttertoast.showToast(
        msg: 'لا توجد بيانات بانتظار المزامنة',
        backgroundColor: AppColors.info,
        textColor: Colors.white,
      );
      return;
    }
    if (!grading.isOnline) {
      Fluttertoast.showToast(
        msg: 'يرجى الاتصال بالإنترنت أولاً',
        backgroundColor: AppColors.warning,
        textColor: Colors.white,
      );
      return;
    }
    final pendingBefore = grading.pendingCount;
    final synced = await grading.syncPendingGrades();
    if (!mounted) return;
    String msg;
    Color bg;
    if (synced > 0) {
      msg = 'تمت مزامنة $synced عنصر بنجاح ✅';
      bg = AppColors.success;
    } else if (pendingBefore == 0) {
      msg = 'لا توجد بيانات بانتظار المزامنة';
      bg = AppColors.info;
    } else {
      msg = 'فشلت المزامنة — تحقق من الاتصال';
      bg = AppColors.error;
    }
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: bg,
      textColor: Colors.white,
    );
  }

  Future<void> _confirmClearCache() async {
    final pendingCount = StorageService.pendingCount;
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.error, size: 26),
            const SizedBox(width: 8),
            Text(
              'تأكيد المسح',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          pendingCount > 0
              ? 'لديك $pendingCount عملية مزامنة معلقة لم تُرسل بعد.\n'
                  'سيتم حذف جميع البيانات المؤقتة والإعدادات المحلية. هذه العملية لا يمكن التراجع عنها.'
              : 'سيتم حذف جميع البيانات المؤقتة والإعدادات المحلية. هل أنت متأكد؟',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('حذف نهائياً',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    try {
      await StorageService.clearPendingSyncs();
      if (!mounted) return;
      Fluttertoast.showToast(
        msg: 'تم مسح البيانات المخزنة',
        backgroundColor: AppColors.success,
        textColor: Colors.white,
      );
    } catch (e) {
      if (!mounted) return;
      Fluttertoast.showToast(
        msg: 'تعذر مسح البيانات',
        backgroundColor: AppColors.error,
        textColor: Colors.white,
      );
    }
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.help_outline, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'المساعدة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _helpRow('🎤', 'استخدم زر الميكروفون لإدخال الدرجات صوتياً'),
              _helpRow('🔢', 'يمكنك قول الأرقام بالعربية أو بالأرقام مباشرة'),
              _helpRow('📊', 'اطلع على الإحصائيات من زر التحليلات'),
              _helpRow('💾', 'احفظ الدرجات قبل الانتقال للطالب التالي'),
              _helpRow('☁️', 'يعمل التطبيق أوفلاين ويتزامن تلقائياً'),
              _helpRow('📤', 'يمكنك تصدير الدرجات بصيغة CSV'),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('فهمت', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _helpRow(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.cairo(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeveloperInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            const Text('👨‍💻', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 8),
            Text(
              'معلومات المطور',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  const Icon(Icons.engineering_rounded,
                      color: Colors.white, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    AdminService.developerName,
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'مطور ${AdminService.appNameAr}',
                    style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _devInfoRow(
              Icons.phone_rounded,
              'واتساب',
              AdminService.developerPhone,
            ),
            _devInfoRow(
              Icons.email_rounded,
              'البريد الإلكتروني',
              AdminService.developerEmail,
            ),
            _devInfoRow(
              Icons.apps_rounded,
              'التطبيق',
              '${AdminService.appName} v${AdminService.appVersion}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إغلاق', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SubscriptionScreen()),
              );
            },
            child:
                Text('الاشتراكات', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _devInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.cairo(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
              Text(
                value,
                style: GoogleFonts.cairo(
                    fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'تأكيد الخروج',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل تريد تسجيل الخروج من التطبيق؟',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('خروج', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}
