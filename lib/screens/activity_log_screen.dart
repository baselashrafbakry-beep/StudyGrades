import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../models/pending_sync.dart';
import '../providers/grading_provider.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// شاشة سجل النشاطات - عرض المزامنات المعلقة والمكتملة
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  List<PendingSync> _pending = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _pending = StorageService.getPendingSyncs();
    });
  }

  Future<void> _syncAll() async {
    final grading = context.read<GradingProvider>();
    if (!grading.isOnline) {
      Fluttertoast.showToast(
        msg: 'يرجى الاتصال بالإنترنت أولاً',
        backgroundColor: AppColors.warning,
        textColor: Colors.white,
      );
      return;
    }
    final synced = await grading.syncPendingGrades();
    if (!mounted) return;
    Fluttertoast.showToast(
      msg: synced > 0 ? 'تمت مزامنة $synced عنصر بنجاح' : 'فشلت المزامنة',
      backgroundColor: synced > 0 ? AppColors.success : AppColors.error,
      textColor: Colors.white,
    );
    _refresh();
  }

  Future<void> _clearAll() async {
    if (_pending.isEmpty) {
      Fluttertoast.showToast(
        msg: 'لا توجد معلقات لحذفها',
        backgroundColor: AppColors.warning,
        textColor: Colors.white,
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.error,
              size: 26,
            ),
            const SizedBox(width: 8),
            Text(
              'حذف جميع المعلقات',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'سيتم حذف ${_pending.length} عملية مزامنة معلقة بشكل نهائي.\n'
          'البيانات غير المرسلة ستُفقد ولا يمكن استرجاعها.',
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
            child: Text(
              'حذف الكل',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await StorageService.clearPendingSyncs();
      if (!mounted) return;
      _refresh();
      Fluttertoast.showToast(
        msg: 'تم حذف جميع المعلقات',
        backgroundColor: AppColors.success,
        textColor: Colors.white,
      );
    } catch (e) {
      if (!mounted) return;
      Fluttertoast.showToast(
        msg: 'تعذر حذف المعلقات',
        backgroundColor: AppColors.error,
        textColor: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final grading = context.watch<GradingProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(grading),
            Expanded(
              child: _pending.isEmpty
                  ? _emptyState()
                  : RefreshIndicator(
                      onRefresh: () async => _refresh(),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
                        itemCount: _pending.length,
                        itemBuilder: (_, i) => _buildLogItem(_pending[i]),
                      ),
                    ),
            ),
            if (_pending.isNotEmpty) _buildBottomBar(grading),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(GradingProvider grading) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
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
                  'سجل النشاطات',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      grading.isOnline
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      grading.isOnline ? 'متصل' : 'غير متصل',
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_pending.length} معلق',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 60),
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_done_rounded,
                size: 80,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'كل البيانات متزامنة! ✨',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'لا توجد عمليات معلقة بانتظار المزامنة',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogItem(PendingSync item) {
    DateTime? time;
    try {
      time = DateTime.parse(item.timestamp);
    } catch (_) {
      // Invalid timestamp - fall back to raw string
    }
    final dateStr = time != null
        ? DateFormat('dd/MM/yyyy - hh:mm a', 'ar').format(time)
        : item.timestamp;

    final totalGrade = item.grades.values.fold<double>(0, (a, b) => a + b);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.cloud_upload_outlined,
                  color: AppColors.warning,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      item.studentName.isEmpty
                          ? 'طالب #${item.studentId}'
                          : item.studentName,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.subject,
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'فصل ${item.classId}',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        dateStr,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6,
                  runSpacing: 4,
                  children: item.grades.entries.map((e) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${e.key}: ${_fmt(e.value)}',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'المجموع: ${_fmt(totalGrade)}',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(GradingProvider grading) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _clearAll,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(
                  'حذف الكل',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: grading.isSyncing ? null : _syncAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: grading.isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.cloud_upload_rounded, size: 18),
                label: Text(
                  grading.isSyncing ? 'جاري المزامنة...' : 'مزامنة الكل',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}
