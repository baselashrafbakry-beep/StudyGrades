import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/admin_service.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';

/// شاشة سجل النشاطات الإدارية
class AdminActivityLogScreen extends StatefulWidget {
  const AdminActivityLogScreen({super.key});

  @override
  State<AdminActivityLogScreen> createState() => _AdminActivityLogScreenState();
}

class _AdminActivityLogScreenState extends State<AdminActivityLogScreen> {
  List<Map<String, dynamic>> _activities = [];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final activities = await AdminService.getActivityLog();
    if (!mounted) return;
    setState(() {
      _activities = activities;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return _activities;
    return _activities.where((a) => a['type'] == _filter).toList();
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'إنشاء حساب':
        return AppColors.success;
      case 'حذف حساب':
        return AppColors.error;
      case 'تعديل حساب':
        return AppColors.info;
      case 'تجميد':
        return AppColors.warning;
      case 'تفعيل':
        return AppColors.success;
      case 'تغيير كلمة المرور':
        return const Color(0xFF6A1B9A);
      case 'إعدادات النظام':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'إنشاء حساب':
        return Icons.person_add_rounded;
      case 'حذف حساب':
        return Icons.person_remove_rounded;
      case 'تعديل حساب':
        return Icons.edit_rounded;
      case 'تجميد':
        return Icons.block_rounded;
      case 'تفعيل':
        return Icons.check_circle_rounded;
      case 'تغيير كلمة المرور':
        return Icons.lock_reset_rounded;
      case 'إعدادات النظام':
        return Icons.settings_rounded;
      case 'تهيئة':
        return Icons.rocket_launch_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<
        ThemeProvider>(); // يضمن إعادة البناء فوراً عند تبديل الوضع الليلي/الفاتح
    final df = DateFormat('dd/MM/yyyy - HH:mm', 'ar');
    final types = _activities.map((a) => a['type'] as String).toSet().toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (types.isNotEmpty) _buildFilterChips(types),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
                            itemCount: _filtered.length,
                            itemBuilder: (ctx, i) {
                              final a = _filtered[i];
                              final type = a['type']?.toString() ?? '';
                              final desc = a['description']?.toString() ?? '';
                              DateTime? ts;
                              try {
                                ts = DateTime.parse(a['timestamp'] ?? '');
                              } catch (_) {
                                // Invalid timestamp - leave ts null
                              }
                              final color = _typeColor(type);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBackground,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.03),
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
                                      child: Icon(_typeIcon(type),
                                          color: color, size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              if (ts != null)
                                                Text(
                                                  df.format(ts),
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 10,
                                                    color: AppColors.textHint,
                                                  ),
                                                ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: color.withValues(
                                                      alpha: 0.13),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  type,
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: color,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            desc,
                                            textAlign: TextAlign.right,
                                            style: GoogleFonts.cairo(
                                              fontSize: 12,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
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
            child: Column(
              children: [
                Text(
                  'سجل العمليات الإدارية',
                  style: GoogleFonts.cairo(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${_activities.length} عملية مسجلة',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
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

  Widget _buildFilterChips(List<String> types) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: AppColors.cardBackground,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _chip('الكل', 'all'),
            ...types.map((t) => _chip(t, t)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: FilterChip(
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        label: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 11,
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.background,
        selectedColor: AppColors.primary,
        showCheckmark: false,
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 76, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'لا توجد عمليات مسجلة',
            style: GoogleFonts.cairo(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
