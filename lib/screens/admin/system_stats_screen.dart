import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/user_model.dart';
import '../../services/admin_service.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';

/// شاشة إحصاءات النظام التفصيلية - للمطور والمدير
class SystemStatsScreen extends StatefulWidget {
  const SystemStatsScreen({super.key});

  @override
  State<SystemStatsScreen> createState() => _SystemStatsScreenState();
}

class _SystemStatsScreenState extends State<SystemStatsScreen> {
  Map<String, dynamic> _stats = {};
  List<User> _users = [];
  Map<String, int> _analyticsCounters = {};
  String? _analyticsLastUpdated;
  bool _analyticsEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await AdminService.getSystemStats();
      final users = await AdminService.getAllUsers();
      final analyticsEnabled = await AdminService.isAnalyticsEnabled();
      final counters = await AdminService.getAnalyticsCounters();
      final lastUpdated = await AdminService.getAnalyticsLastUpdated();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _users = users;
        _analyticsEnabled = analyticsEnabled;
        _analyticsCounters = counters;
        _analyticsLastUpdated = lastUpdated;
        _loading = false;
      });
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'SystemStats.load');
      if (!mounted) return;
      setState(() => _loading = false);
    }
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
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
                        children: [
                          _buildOverviewCards(),
                          const SizedBox(height: 16),
                          _buildPieChartSection(),
                          const SizedBox(height: 16),
                          _buildBarChartSection(),
                          const SizedBox(height: 16),
                          _buildUsageAnalyticsSection(),
                          const SizedBox(height: 16),
                          _buildRecentUsers(),
                        ],
                      ),
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
              'إحصاءات النظام',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCards() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1976D2), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'نظرة عامة',
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_stats['total_users'] ?? 0}',
            style: GoogleFonts.cairo(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            'إجمالي الحسابات',
            style: GoogleFonts.cairo(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  '${_stats['active_users'] ?? 0}',
                  'نشط',
                  Icons.check_circle,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              Expanded(
                child: _miniStat(
                  '${_stats['inactive_users'] ?? 0}',
                  'موقوف',
                  Icons.block,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              Expanded(
                child: _miniStat(
                  '${_stats['new_users_week'] ?? 0}',
                  'جديد (٧ أيام)',
                  Icons.trending_up,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(
            fontSize: 9,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  Widget _buildPieChartSection() {
    final dev = _stats['developers'] ?? 0;
    final adm = _stats['admins'] ?? 0;
    final mgr = _stats['managers'] ?? 0;
    final tch = _stats['teachers'] ?? 0;
    final total = dev + adm + mgr + tch;

    if (total == 0) {
      return _emptyChartCard('توزيع الأدوار');
    }

    final sections = <PieChartSectionData>[];
    void add(int v, Color c, String label) {
      if (v == 0) return;
      final percent = (v / total * 100).toStringAsFixed(0);
      sections.add(PieChartSectionData(
        value: v.toDouble(),
        color: c,
        title: '$percent%',
        radius: 60,
        titleStyle: GoogleFonts.cairo(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ));
    }

    add(dev, const Color(0xFF6A1B9A), 'مطور');
    add(adm, AppColors.error, 'مدير');
    add(mgr, AppColors.warning, 'مشرف');
    add(tch, AppColors.primary, 'معلم');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'توزيع الأدوار',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 38,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _legend('مطور', const Color(0xFF6A1B9A), dev),
              _legend('مدير', AppColors.error, adm),
              _legend('مشرف', AppColors.warning, mgr),
              _legend('معلم', AppColors.primary, tch),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(String label, Color color, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '$label ($count)',
          style: GoogleFonts.cairo(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildBarChartSection() {
    final active = (_stats['active_users'] ?? 0).toDouble();
    final inactive = (_stats['inactive_users'] ?? 0).toDouble();
    final newWeek = (_stats['new_users_week'] ?? 0).toDouble();
    final total = (_stats['total_users'] ?? 0).toDouble();
    final maxV = [active, inactive, newWeek, total]
        .reduce((a, b) => a > b ? a : b)
        .clamp(1.0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, color: AppColors.success),
              const SizedBox(width: 8),
              Text(
                'مقارنة الحسابات',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxV * 1.2,
                barGroups: [
                  _bar(0, total, AppColors.primary),
                  _bar(1, active, AppColors.success),
                  _bar(2, inactive, AppColors.error),
                  _bar(3, newWeek, AppColors.warning),
                ],
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, _) {
                        const labels = ['الكل', 'نشط', 'موقوف', 'جديد'];
                        final i = v.toInt();
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[i],
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _bar(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 28,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
      ],
    );
  }

  Widget _emptyChartCard(String title) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(title, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Icon(Icons.inbox_rounded, size: 48, color: Colors.grey),
          const SizedBox(height: 6),
          Text(
            'لا توجد بيانات للعرض',
            style: GoogleFonts.cairo(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// عدّادات استخدام حقيقية (محلية بالكامل، بدون أي اتصال خارجي) —
  /// تُحسب فقط عندما يكون "تفعيل التحليلات" مفعّلاً من إعدادات النظام.
  static const Map<String, String> _eventLabelsAr = {
    'grading_session_started': 'جلسات رصد بدأت',
    'grade_synced_online': 'درجات تمت مزامنتها فوراً',
    'grade_saved_locally': 'درجات حُفظت محلياً (أوفلاين)',
    'excel_export_completed': 'ملفات Excel تم تصديرها',
  };

  Widget _buildUsageAnalyticsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'إحصاءات الاستخدام (محلية)',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (!_analyticsEnabled)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'معطّلة',
                    style: GoogleFonts.cairo(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: AppColors.error,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'عدّادات مجهولة الهوية تُحسب على هذا الجهاز فقط — لا تُرسَل '
            'لأي خادم خارجي. يمكن تعطيلها كلياً من "إعدادات النظام".',
            style: GoogleFonts.cairo(
              fontSize: 10,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          if (!_analyticsEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'التحليلات معطّلة حالياً — لن يتم تسجيل أي أحداث جديدة',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (_analyticsCounters.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'لا توجد بيانات استخدام مسجّلة بعد',
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else ...[
            ..._analyticsCounters.entries.map((e) {
              final label = _eventLabelsAr[e.key] ?? e.key;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${e.value}',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (_analyticsLastUpdated != null) ...[
              const SizedBox(height: 8),
              Text(
                'آخر تحديث: ${_formatDate(_analyticsLastUpdated!)}',
                style: GoogleFonts.cairo(
                  fontSize: 9,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/'
          '${d.day.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  Widget _buildRecentUsers() {
    final recent = List<User>.from(_users);
    recent.sort((a, b) {
      final ad = a.createdAt ?? DateTime(2000);
      final bd = b.createdAt ?? DateTime(2000);
      return bd.compareTo(ad);
    });
    final shown = recent.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: AppColors.info),
              const SizedBox(width: 8),
              Text(
                'أحدث الحسابات',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'لا توجد حسابات',
                style: GoogleFonts.cairo(color: AppColors.textSecondary),
              ),
            )
          else
            ...shown.map(_buildUserRow),
        ],
      ),
    );
  }

  Widget _buildUserRow(User user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                UserRole.icon(user.role),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  user.displayName,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '@${user.username} • ${UserRole.label(user.role)}',
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: user.isActive
                  ? AppColors.success.withValues(alpha: 0.13)
                  : AppColors.error.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              user.isActive ? 'نشط' : 'موقوف',
              style: GoogleFonts.cairo(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: user.isActive ? AppColors.success : AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
