import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/admin_service.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';

/// شاشة إعدادات النظام - للمطور فقط
class SystemSettingsScreen extends StatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  final _apiUrlCtrl = TextEditingController();
  final _appNameCtrl = TextEditingController();
  final _supportEmailCtrl = TextEditingController();
  bool _maintenanceMode = false;
  bool _enableAnalytics = true;
  bool _enableServerSpeech = true;
  bool _enableOfflineMode = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _apiUrlCtrl.text = await AdminService.getSystemSetting<String>(
          'api_url',
          defaultValue: 'https://studygrades2026.pythonanywhere.com/api/mobile',
        ) ??
        '';
    _appNameCtrl.text = await AdminService.getSystemSetting<String>(
          'app_name',
          defaultValue: AdminService.appName,
        ) ??
        AdminService.appName;
    _supportEmailCtrl.text = await AdminService.getSystemSetting<String>(
          'support_email',
          defaultValue: AdminService.developerEmail,
        ) ??
        AdminService.developerEmail;
    _maintenanceMode = await AdminService.getSystemSetting<bool>(
          'maintenance_mode',
          defaultValue: false,
        ) ??
        false;
    _enableAnalytics = await AdminService.getSystemSetting<bool>(
          'enable_analytics',
          defaultValue: true,
        ) ??
        true;
    _enableServerSpeech = await AdminService.getSystemSetting<bool>(
          'enable_server_speech',
          defaultValue: true,
        ) ??
        true;
    _enableOfflineMode = await AdminService.getSystemSetting<bool>(
          'enable_offline_mode',
          defaultValue: true,
        ) ??
        true;
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _apiUrlCtrl.dispose();
    _appNameCtrl.dispose();
    _supportEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAll() async {
    await AdminService.setSystemSetting('api_url', _apiUrlCtrl.text.trim());
    await AdminService.setSystemSetting('app_name', _appNameCtrl.text.trim());
    await AdminService.setSystemSetting(
        'support_email', _supportEmailCtrl.text.trim());
    await AdminService.setSystemSetting('maintenance_mode', _maintenanceMode);
    await AdminService.setSystemSetting('enable_analytics', _enableAnalytics);
    await AdminService.setSystemSetting(
        'enable_server_speech', _enableServerSpeech);
    await AdminService.setSystemSetting(
        'enable_offline_mode', _enableOfflineMode);

    Fluttertoast.showToast(
      msg: 'تم حفظ الإعدادات بنجاح',
      backgroundColor: AppColors.success,
      textColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<
        ThemeProvider>(); // يضمن إعادة البناء فوراً عند تبديل الوضع الليلي/الفاتح
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
                      children: [
                        _buildWarningBanner(),
                        const SizedBox(height: 14),
                        _section('معلومات التطبيق', Icons.info_rounded),
                        _textTile(
                          ctrl: _appNameCtrl,
                          icon: Icons.title_rounded,
                          label: 'اسم التطبيق',
                        ),
                        _textTile(
                          ctrl: _apiUrlCtrl,
                          icon: Icons.api_rounded,
                          label: 'رابط الخادم (API URL)',
                        ),
                        _textTile(
                          ctrl: _supportEmailCtrl,
                          icon: Icons.email_rounded,
                          label: 'بريد الدعم',
                        ),
                        const SizedBox(height: 14),
                        _section('التحكم العام', Icons.toggle_on_rounded),
                        _switchTile(
                          icon: Icons.engineering_rounded,
                          color: AppColors.error,
                          title: 'وضع الصيانة',
                          subtitle: 'إيقاف التطبيق مؤقتاً لجميع المستخدمين',
                          value: _maintenanceMode,
                          onChanged: (v) =>
                              setState(() => _maintenanceMode = v),
                        ),
                        _switchTile(
                          icon: Icons.analytics_rounded,
                          color: AppColors.info,
                          title: 'تفعيل التحليلات',
                          subtitle: 'جمع إحصاءات الاستخدام للتحسين',
                          value: _enableAnalytics,
                          onChanged: (v) =>
                              setState(() => _enableAnalytics = v),
                        ),
                        const SizedBox(height: 14),
                        _section('الميزات', Icons.extension_rounded),
                        _switchTile(
                          icon: Icons.cloud_rounded,
                          color: AppColors.success,
                          title: 'الإدخال الصوتي السحابي',
                          subtitle: 'تفعيل Whisper AI للمستخدمين',
                          value: _enableServerSpeech,
                          onChanged: (v) =>
                              setState(() => _enableServerSpeech = v),
                        ),
                        _switchTile(
                          icon: Icons.cloud_off_rounded,
                          color: AppColors.primary,
                          title: 'الوضع الأوفلاين',
                          subtitle: 'السماح بالعمل بدون إنترنت',
                          value: _enableOfflineMode,
                          onChanged: (v) =>
                              setState(() => _enableOfflineMode = v),
                        ),
                        const SizedBox(height: 20),
                        _buildDangerZone(),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _saveAll,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.save_rounded),
                          label: Text(
                            'حفظ كل الإعدادات',
                            style: GoogleFonts.cairo(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6A1B9A), Color(0xFF1A237E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ),
          Expanded(
            child: Text(
              'إعدادات النظام',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_rounded, color: AppColors.warning, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'هذه الإعدادات تؤثر على جميع المستخدمين. كن حذراً عند التعديل.',
              style: GoogleFonts.cairo(
                fontSize: 12,
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _textTile({
    required TextEditingController ctrl,
    required IconData icon,
    required String label,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
          ),
        ],
      ),
      child: TextField(
        controller: ctrl,
        style: GoogleFonts.cairo(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.cairo(fontSize: 12),
          prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
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
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: color,
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZone() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.dangerous_rounded, color: AppColors.error),
              const SizedBox(width: 8),
              Text(
                'منطقة الخطر',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'هذه الإجراءات لا يمكن التراجع عنها',
            style: GoogleFonts.cairo(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _confirmClearLog,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              minimumSize: const Size(double.infinity, 42),
            ),
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: Text(
              'مسح سجل النشاطات بالكامل',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearLog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'تأكيد الحذف',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل تريد مسح سجل النشاطات بالكامل؟',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('مسح',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AdminService.clearActivityLog();
      Fluttertoast.showToast(
        msg: 'تم مسح السجل',
        backgroundColor: AppColors.success,
        textColor: Colors.white,
      );
    }
  }
}
