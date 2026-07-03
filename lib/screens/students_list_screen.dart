import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/student_model.dart';
import '../providers/grading_provider.dart';
import '../theme/app_theme.dart';

/// شاشة قائمة الطلاب — تعرض جميع الطلاب مع درجاتهم وتسمح بالتنقل السريع
class StudentsListScreen extends StatefulWidget {
  final String className;
  final String subject;

  const StudentsListScreen({
    super.key,
    required this.className,
    required this.subject,
  });

  @override
  State<StudentsListScreen> createState() => _StudentsListScreenState();
}

class _StudentsListScreenState extends State<StudentsListScreen> {
  String _search = '';
  _SortMode _sortMode = _SortMode.original;
  _FilterMode _filterMode = _FilterMode.all;

  @override
  Widget build(BuildContext context) {
    final grading = context.watch<GradingProvider>();
    final allStudents = grading.students;
    final fields = grading.fields;
    final totalPossible = fields.fold<double>(0, (s, f) => s + f.max);

    // Filter
    var filtered = allStudents.where((s) {
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!s.name.toLowerCase().contains(q) &&
            !s.studentNumber.toLowerCase().contains(q)) {
          return false;
        }
      }
      switch (_filterMode) {
        case _FilterMode.all:
          return true;
        case _FilterMode.completed:
          return s.grades.length >= fields.length && fields.isNotEmpty;
        case _FilterMode.pending:
          return s.grades.length < fields.length;
        case _FilterMode.passed:
          return totalPossible > 0 && s.total >= totalPossible * 0.5;
        case _FilterMode.failed:
          return totalPossible > 0 &&
              s.grades.isNotEmpty &&
              s.total < totalPossible * 0.5;
      }
    }).toList();

    // Sort
    final indexed = filtered.map((s) {
      return MapEntry(allStudents.indexOf(s), s);
    }).toList();

    switch (_sortMode) {
      case _SortMode.original:
        indexed.sort((a, b) => a.key.compareTo(b.key));
        break;
      case _SortMode.nameAsc:
        indexed.sort((a, b) => a.value.name.compareTo(b.value.name));
        break;
      case _SortMode.totalDesc:
        indexed.sort((a, b) => b.value.total.compareTo(a.value.total));
        break;
      case _SortMode.totalAsc:
        indexed.sort((a, b) => a.value.total.compareTo(b.value.total));
        break;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(allStudents.length, filtered.length),
            _buildSearchAndFilters(),
            Expanded(
              child: indexed.isEmpty
                  ? _emptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                      itemCount: indexed.length,
                      itemBuilder: (_, i) {
                        final entry = indexed[i];
                        return _buildStudentTile(
                          entry.value,
                          entry.key,
                          fields,
                          totalPossible,
                          grading,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int total, int shown) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
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
                child: Column(
                  children: [
                    Text(
                      'قائمة الطلاب',
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${widget.className} • ${widget.subject}',
                      style: GoogleFonts.cairo(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$shown / $total',
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

  Widget _buildSearchAndFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        children: [
          TextField(
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: 'ابحث باسم الطالب أو رقم الجلوس...',
              hintStyle: GoogleFonts.cairo(
                color: AppColors.textHint,
                fontSize: 13,
              ),
              prefixIcon: Icon(Icons.search, color: AppColors.textHint),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 14,
              ),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip('الكل', _FilterMode.all),
                const SizedBox(width: 6),
                _filterChip('مكتمل', _FilterMode.completed),
                const SizedBox(width: 6),
                _filterChip('معلّق', _FilterMode.pending),
                const SizedBox(width: 6),
                _filterChip('ناجح', _FilterMode.passed),
                const SizedBox(width: 6),
                _filterChip('راسب', _FilterMode.failed),
                const SizedBox(width: 12),
                Container(width: 1, color: Colors.grey.shade300),
                const SizedBox(width: 12),
                _sortChip('الترتيب الأصلي', _SortMode.original),
                const SizedBox(width: 6),
                _sortChip('الاسم', _SortMode.nameAsc),
                const SizedBox(width: 6),
                _sortChip('الأعلى', _SortMode.totalDesc),
                const SizedBox(width: 6),
                _sortChip('الأقل', _SortMode.totalAsc),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _FilterMode mode) {
    final selected = _filterMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _filterMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _sortChip(String label, _SortMode mode) {
    final selected = _sortMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _sortMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.info.withValues(alpha: 0.15)
              : AppColors.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.info : Colors.grey.shade300,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sort_rounded,
              size: 14,
              color: selected ? AppColors.info : AppColors.textHint,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.info : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentTile(
    Student student,
    int originalIndex,
    List<GradeField> fields,
    double totalPossible,
    GradingProvider grading,
  ) {
    final percent = totalPossible > 0
        ? (student.total / totalPossible).clamp(0.0, 1.0)
        : 0.0;
    final isCurrent = grading.currentIndex == originalIndex;
    final completedFields = student.grades.length;
    final isCompleted =
        fields.isNotEmpty && completedFields >= fields.length;

    final color = !isCompleted
        ? AppColors.textHint
        : percent >= 0.7
            ? AppColors.success
            : percent >= 0.5
                ? AppColors.warning
                : AppColors.error;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent ? AppColors.primary : Colors.grey.shade200,
          width: isCurrent ? 2 : 1,
        ),
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
        onTap: () {
          grading.setCurrentIndex(originalIndex);
          Navigator.pop(context);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar / Index
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: isCurrent
                      ? AppColors.primaryGradient
                      : LinearGradient(
                          colors: [
                            color.withValues(alpha: 0.18),
                            color.withValues(alpha: 0.10),
                          ],
                        ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    '${originalIndex + 1}',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isCurrent ? Colors.white : color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        if (isCompleted)
                          const Icon(
                            Icons.check_circle,
                            size: 16,
                            color: AppColors.success,
                          ),
                        if (isCompleted) const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            student.name,
                            textAlign: TextAlign.right,
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'رقم: ${student.studentNumber}',
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$completedFields / ${fields.length} بنود',
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percent,
                        minHeight: 5,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _fmt(student.total),
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    'من ${_fmt(totalPossible)}',
                    style: GoogleFonts.cairo(
                      fontSize: 9,
                      color: AppColors.textHint,
                    ),
                  ),
                  Text(
                    '${(percent * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 14),
          Text(
            _search.isNotEmpty
                ? 'لا يوجد طلاب يطابقون البحث'
                : 'لا يوجد طلاب في هذا التصنيف',
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

enum _SortMode { original, nameAsc, totalDesc, totalAsc }

enum _FilterMode { all, completed, pending, passed, failed }
