import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';
import 'users_management_screen.dart';
import 'system_stats_screen.dart';
import 'system_settings_screen.dart';
import 'admin_activity_log_screen.dart';
import 'license_generator_screen.dart';

/// لوحة تحكم المطور والمدير الرئيسية
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  Map<String, dynamic> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      final stats = await AdminService.getSystemStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'AdminPanel.loadStats');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    // تحقق من الصلاحيات
    if (user == null || !user.canAccessAdminPanel) {
      return _buildNoAccess();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadStats,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildHeader(user),
              const SizedBox(height: 16),
              _buildStatsGrid(),
              const SizedBox(height: 16),
              _buildSection('الإدارة', Icons.admin_panel_settings_rounded),
              _buildAdminMenu(user),
              const SizedBox(height: 16),
              _buildSection('التحليلات والمراقبة', Icons.analytics_outlined),
              _buildAnalyticsMenu(user),
              if (user.canEditSystemSettings) ...[
                const SizedBox(height: 16),
                _buildSection('إعدادات النظام (المطور)',
                    Icons.settings_applications_rounded),
                _buildDeveloperMenu(),
              ],
              const SizedBox(height: 30),
              _buildFooter(user),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(User user) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6A1B9A), Color(0xFF4A148C), Color(0xFF1A237E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      UserRole.icon(user.role),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      UserRole.label(user.role),
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Color(0xFF6A1B9A),
              size: 40,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'لوحة تحكم المطوّر',
            style: GoogleFonts.cairo(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'مرحباً ${user.displayName}',
            style: GoogleFonts.cairo(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final df = DateFormat('dd/MM HH:mm', 'ar');
    final lastActivity = _stats['last_activity'] as DateTime?;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _statCard(
                  icon: Icons.people_alt_rounded,
                  value: '${_stats['total_users'] ?? 0}',
                  label: 'إجمالي الحسابات',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statCard(
                  icon: Icons.check_circle_rounded,
                  value: '${_stats['active_users'] ?? 0}',
                  label: 'حساب نشط',
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  icon: Icons.shield_rounded,
                  value: '${_stats['admins'] ?? 0}',
                  label: 'مدير',
                  color: AppColors.error,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statCard(
                  icon: Icons.school_rounded,
                  value: '${_stats['managers'] ?? 0}',
                  label: 'مشرف',
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statCard(
                  icon: Icons.book_rounded,
                  value: '${_stats['teachers'] ?? 0}',
                  label: 'معلم',
                  color: AppColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.08),
                  AppColors.primary.withValues(alpha: 0.02),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.access_time_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'آخر نشاط في النظام',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        lastActivity != null
                            ? df.format(lastActivity)
                            : 'لا يوجد نشاط',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_stats['total_activities'] ?? 0} نشاط',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
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

  Widget _statCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
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

  Widget _buildAdminMenu(User user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          _menuTile(
            icon: Icons.people_alt_rounded,
            iconColor: AppColors.primary,
            title: 'إدارة المستخدمين',
            subtitle:
                'إنشاء وتعديل وحذف الحسابات • ${_stats['total_users'] ?? 0} حساب',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const UsersManagementScreen(),
              ),
            ).then((_) => _loadStats()),
          ),
          _menuTile(
            icon: Icons.shield_rounded,
            iconColor: AppColors.error,
            title: 'الصلاحيات والأدوار',
            subtitle: 'مطور / مدير / مشرف / معلم',
            onTap: _showRolesDialog,
          ),
          _menuTile(
            icon: Icons.history_rounded,
            iconColor: AppColors.info,
            title: 'سجل العمليات الإدارية',
            subtitle: '${_stats['total_activities'] ?? 0} عملية مسجلة',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminActivityLogScreen(),
              ),
            ).then((_) => _loadStats()),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsMenu(User user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          _menuTile(
            icon: Icons.bar_chart_rounded,
            iconColor: AppColors.success,
            title: 'إحصاءات النظام الكاملة',
            subtitle: 'تحليل تفصيلي للحسابات والاستخدام',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SystemStatsScreen(),
              ),
            ),
          ),
          _menuTile(
            icon: Icons.trending_up_rounded,
            iconColor: AppColors.warning,
            title: 'حسابات جديدة (آخر 7 أيام)',
            subtitle: '${_stats['new_users_week'] ?? 0} حساب جديد',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SystemStatsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeveloperMenu() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          _menuTile(
            icon: Icons.settings_applications_rounded,
            iconColor: const Color(0xFF6A1B9A),
            title: 'إعدادات النظام العامة',
            subtitle: 'تحكم كامل بإعدادات التطبيق',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SystemSettingsScreen(),
              ),
            ),
          ),
          _menuTile(
            icon: Icons.api_rounded,
            iconColor: AppColors.info,
            title: 'إعدادات الخادم (Backend)',
            subtitle: AdminService.serverUrl,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SystemSettingsScreen(),
              ),
            ),
          ),
          _menuTile(
            icon: Icons.vpn_key_rounded,
            iconColor: const Color(0xFF00897B),
            title: 'توليد رمز اشتراك مخصص',
            subtitle: 'توليد كود مرتبط بجهاز عميل معيّن',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LicenseGeneratorScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
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
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
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
              Icon(
                Icons.arrow_back_ios_rounded,
                size: 14,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(User user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF6A1B9A).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_user_rounded,
                  color: Color(0xFF6A1B9A),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تم تسجيل دخولك بصلاحيات: ${UserRole.label(user.role)}',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: const Color(0xFF6A1B9A),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${AdminService.appName} v${AdminService.appVersion} — Admin Panel',
            style: GoogleFonts.cairo(
              fontSize: 11,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoAccess() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_rounded, size: 80, color: AppColors.error),
              const SizedBox(height: 18),
              Text(
                'لا تملك صلاحية الوصول',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'هذه الشاشة متاحة فقط للمطورين والمدراء',
                style: GoogleFonts.cairo(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: Text('رجوع', style: GoogleFonts.cairo()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRolesDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.shield_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('الأدوار والصلاحيات',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _roleInfoTile(
                icon: '👨‍💻',
                title: UserRole.label(UserRole.developer),
                description: 'صلاحيات كاملة - تحكم بالنظام بأكمله',
                color: const Color(0xFF6A1B9A),
              ),
              _roleInfoTile(
                icon: '🛡️',
                title: UserRole.label(UserRole.admin),
                description: 'إدارة المستخدمين وعرض الإحصاءات',
                color: AppColors.error,
              ),
              _roleInfoTile(
                icon: '🎓',
                title: UserRole.label(UserRole.manager),
                description: 'إشراف على المعلمين ومتابعة الدرجات',
                color: AppColors.warning,
              ),
              _roleInfoTile(
                icon: '📚',
                title: UserRole.label(UserRole.teacher),
                description: 'رصد درجات الطلاب صوتياً',
                color: AppColors.primary,
              ),
            ],
          ),
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

  Widget _roleInfoTile({
    required String icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(icon, style: const TextStyle(fontSize: 20)),
            ),
          ),
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
                    color: color,
                  ),
                ),
                Text(
                  description,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
