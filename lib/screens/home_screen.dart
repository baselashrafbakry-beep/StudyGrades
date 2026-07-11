import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../models/hierarchy_model.dart';
import '../providers/auth_provider.dart';
import '../providers/grading_provider.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';
import 'subject_selection_screen.dart';
import 'settings_screen.dart';
import 'activity_log_screen.dart';
import 'dashboard_screen.dart';
import 'grading_screen.dart';

/// شاشة اختيار المادة للعرض التجريبي (بدون API)
class SubjectSelectionScreenDemo extends StatelessWidget {
  const SubjectSelectionScreenDemo({super.key});

  @override
  Widget build(BuildContext context) {
    final grading = context.read<GradingProvider>();
    // بيانات تجريبية جاهزة - انتقل مباشرة لشاشة الرصد
    if (grading.classroom == null) {
      grading.loadDemoClassroom(className: 'فصل تجريبي أ', subject: 'عام');
    }
    return const GradingScreen(
      classId: 0,
      className: 'فصل تجريبي أ',
      subject: 'عام',
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<HierarchyItem> _hierarchy = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await apiClient.getHierarchy();
      if (!mounted) return;
      setState(() {
        _hierarchy = data;
        _loading = false;
      });
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'HomeScreen.fetchHierarchy');
      if (!mounted) return;
      setState(() {
        _error = ErrorHandler.humanize(e);
        _loading = false;
      });
    }
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
            _buildHeader(auth, grading),
            if (!grading.isOnline) _offlineBanner(grading.pendingCount),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetch,
                color: AppColors.primary,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [_buildQuickActions(), _buildBody()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AuthProvider auth, GradingProvider grading) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                tooltip: 'الإعدادات',
                icon: const Icon(Icons.settings_rounded, color: Colors.white),
              ),
              IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
                ),
                tooltip: 'سجل النشاطات',
                icon: const Icon(Icons.history_rounded, color: Colors.white),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: grading.isOnline
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      grading.isOnline ? 'متصل' : 'غير متصل',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'مرحباً 👋',
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  Text(
                    auth.user?.username ?? 'المعلم',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    auth.user == null
                        ? 'بدون اشتراك'
                        : '${auth.user!.subscription.planLabel} • ${auth.user!.subscription.statusLabel}',
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _statBadge(
                  icon: Icons.school_outlined,
                  label: 'المراحل',
                  value: '${_hierarchy.length}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statBadge(
                  icon: Icons.class_outlined,
                  label: 'الفصول',
                  value:
                      '${_hierarchy.fold<int>(0, (s, h) => s + h.classes.length)}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statBadge(
                  icon: Icons.cloud_sync_outlined,
                  label: 'بانتظار المزامنة',
                  value: '${grading.pendingCount}',
                  highlight: grading.pendingCount > 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBadge({
    required IconData icon,
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.warning.withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.cairo(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _offlineBanner(int pending) {
    return Container(
      width: double.infinity,
      color: AppColors.warning.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            color: AppColors.warning,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pending > 0
                  ? 'وضع أوفلاين - $pending درجة بانتظار المزامنة'
                  : 'وضع أوفلاين - سيتم الحفظ محلياً',
              style: GoogleFonts.cairo(
                fontSize: 12,
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildShimmer();

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 80),
            Icon(
              Icons.cloud_off_rounded,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 18),
            Text(
              'تعذّر جلب البيانات',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh),
              label: Text('إعادة المحاولة', style: GoogleFonts.cairo()),
            ),
            const SizedBox(height: 18),
            _buildDemoEntryCard(),
          ],
        ),
      );
    }

    if (_hierarchy.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 60),
            Icon(Icons.school_outlined, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 18),
            Text(
              'لا توجد فصول دراسية متاحة',
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'تأكد من الاتصال بالإنترنت وإعداد السيرفر',
              style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            _buildDemoEntryCard(),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 80),
      itemCount: _hierarchy.length + 1,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 12),
            child: Text(
              'اختر المرحلة الدراسية',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.right,
            ),
          );
        }
        final stage = _hierarchy[i - 1];
        return _buildStageCard(stage);
      },
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 12),
            child: Text(
              'إجراءات سريعة',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _quickActionCard(
                  icon: Icons.dashboard_rounded,
                  label: 'لوحة التحكم',
                  color: AppColors.primary,
                  onTap: () {
                    final grading = context.read<GradingProvider>();
                    if (grading.students.isEmpty || grading.classroom == null) {
                      _showSnack('اختر فصلاً ومادة أولاً لعرض لوحة التحكم');
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DashboardScreen(
                          className: grading.classroom!.className,
                          subject: grading.classroom!.subject,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quickActionCard(
                  icon: Icons.history_rounded,
                  label: 'سجل النشاطات',
                  color: AppColors.info,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ActivityLogScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _quickActionCard(
                  icon: Icons.cloud_sync_rounded,
                  label: 'مزامنة الآن',
                  color: AppColors.success,
                  onTap: () async {
                    final grading = context.read<GradingProvider>();
                    if (!grading.isOnline) {
                      _showSnack('لا يوجد اتصال بالإنترنت');
                      return;
                    }
                    if (grading.pendingCount == 0) {
                      _showSnack('لا توجد درجات بانتظار المزامنة');
                      return;
                    }
                    _showSnack('جاري المزامنة...');
                    await grading.syncPendingGrades();
                    if (!mounted) return;
                    _showSnack('تمت المزامنة بنجاح');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quickActionCard(
                  icon: Icons.settings_rounded,
                  label: 'الإعدادات',
                  color: AppColors.warning,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.cairo()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildDemoEntryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.play_circle_outline,
                color: AppColors.info,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'تجربة النظام',
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'جرّب الرصد الصوتي بدون اتصال بالسيرفر (بيانات تجريبية)',
            style: GoogleFonts.cairo(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              final grading = context.read<GradingProvider>();
              grading.loadDemoClassroom(
                className: 'فصل تجريبي أ',
                subject: 'عام',
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SubjectSelectionScreenDemo(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(
              'ابدأ التجربة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageCard(HierarchyItem stage) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          title: Text(
            stage.name,
            style: GoogleFonts.cairo(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.right,
          ),
          subtitle: Text(
            '${stage.classes.length} فصل دراسي',
            style: GoogleFonts.cairo(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.right,
          ),
          children: stage.classes.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      'لا توجد فصول في هذه المرحلة',
                      style: GoogleFonts.cairo(
                        color: AppColors.textHint,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ]
              : stage.classes
                    .map(
                      (c) => InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SubjectSelectionScreen(
                              classId: c.id,
                              className: c.name,
                            ),
                          ),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.class_rounded,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  c.name,
                                  style: GoogleFonts.cairo(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 16,
                                color: AppColors.textHint,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          6,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Shimmer.fromColors(
              baseColor: Colors.grey.shade300,
              highlightColor: Colors.grey.shade100,
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
