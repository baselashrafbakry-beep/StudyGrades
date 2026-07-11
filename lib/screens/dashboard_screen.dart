import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../providers/grading_provider.dart';
import '../models/student_model.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';

/// لوحة تحكم تحليلية متقدمة - Dashboard with Charts
class DashboardScreen extends StatefulWidget {
  final String className;
  final String subject;

  const DashboardScreen({
    super.key,
    required this.className,
    required this.subject,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _touchedBarIndex = -1;

  @override
  Widget build(BuildContext context) {
    final grading = context.watch<GradingProvider>();
    final students = grading.students;
    final fields = grading.fields;
    final stats = AnalyticsService.calculate(students, fields);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: students.isEmpty
                  ? _emptyState()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSummaryCards(stats),
                          const SizedBox(height: 18),
                          _buildCompletionCard(stats),
                          const SizedBox(height: 18),
                          _buildGradeDistribution(students, fields, stats),
                          const SizedBox(height: 18),
                          _buildTopStudentsCard(students, fields, stats),
                          const SizedBox(height: 18),
                          _buildFieldAnalysisCard(students, fields),
                          const SizedBox(height: 18),
                          _buildPassFailPie(students, fields, stats),
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
                child: Column(
                  children: [
                    Text(
                      'لوحة التحليلات',
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 20,
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
              const SizedBox(width: 48),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          Text(
            'لا توجد بيانات لعرضها',
            style: GoogleFonts.cairo(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(ClassStats stats) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: [
        _summaryCard(
          'إجمالي الطلاب',
          '${stats.totalStudents}',
          Icons.people_alt_rounded,
          AppColors.primary,
        ),
        _summaryCard(
          'متوسط الدرجات',
          stats.averageScore.toStringAsFixed(1),
          Icons.trending_up_rounded,
          AppColors.info,
        ),
        _summaryCard(
          'نسبة النجاح',
          '${stats.successRate.toStringAsFixed(0)}%',
          Icons.emoji_events_rounded,
          AppColors.success,
        ),
        _summaryCard(
          'مكتملي البيانات',
          '${stats.completedStudents} / ${stats.totalStudents}',
          Icons.task_alt_rounded,
          AppColors.warning,
        ),
      ],
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionCard(ClassStats stats) {
    final pct = stats.completionPercentage / 100;
    return Container(
      padding: const EdgeInsets.all(18),
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
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.donut_large_rounded,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'تقدم الإنجاز الكلي',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          CircularPercentIndicator(
            radius: 80,
            lineWidth: 14,
            percent: pct,
            animation: true,
            animationDuration: 1200,
            circularStrokeCap: CircularStrokeCap.round,
            backgroundColor: AppColors.background,
            linearGradient: LinearGradient(
              colors: pct >= 0.7
                  ? [AppColors.success, const Color(0xFF2E7D32)]
                  : pct >= 0.4
                  ? [AppColors.warning, const Color(0xFFEF6C00)]
                  : [AppColors.error, const Color(0xFFB71C1C)],
            ),
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${stats.completionPercentage.toStringAsFixed(0)}%',
                  style: GoogleFonts.cairo(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${stats.completedStudents} / ${stats.totalStudents}',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _miniLegend('مكتمل', AppColors.success, stats.completedStudents),
              _miniLegend(
                'متبقي',
                AppColors.textHint,
                stats.totalStudents - stats.completedStudents,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniLegend(String label, Color color, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: $count',
          style: GoogleFonts.cairo(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildGradeDistribution(
    List<Student> students,
    List<GradeField> fields,
    ClassStats stats,
  ) {
    if (stats.totalPossible == 0) return const SizedBox();

    // Distribution buckets: 0-25%, 25-50%, 50-75%, 75-100%
    final buckets = List.filled(4, 0);
    for (final s in students) {
      if (s.grades.isEmpty) continue;
      final pct = (s.totalFor(fields) / stats.totalPossible) * 100;
      if (pct < 25) {
        buckets[0]++;
      } else if (pct < 50) {
        buckets[1]++;
      } else if (pct < 75) {
        buckets[2]++;
      } else {
        buckets[3]++;
      }
    }

    final maxCount = buckets.reduce((a, b) => a > b ? a : b).toDouble();
    final chartMax = maxCount > 0 ? (maxCount * 1.2).ceilToDouble() : 5.0;

    final colors = [
      AppColors.error,
      AppColors.warning,
      AppColors.info,
      AppColors.success,
    ];
    final labels = ['ضعيف', 'مقبول', 'جيد', 'ممتاز'];
    final ranges = ['0-25%', '25-50%', '50-75%', '75-100%'];

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bar_chart_rounded,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'توزيع الدرجات على المستويات',
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: chartMax,
                barTouchData: BarTouchData(
                  touchCallback: (event, response) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          response == null ||
                          response.spot == null) {
                        _touchedBarIndex = -1;
                        return;
                      }
                      _touchedBarIndex = response.spot!.touchedBarGroupIndex;
                    });
                  },
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.textPrimary,
                    getTooltipItem: (group, _, rod, __) {
                      return BarTooltipItem(
                        '${labels[group.x]}\n${rod.toY.toInt()} طالب',
                        GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            children: [
                              Text(
                                labels[i],
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                ranges[i],
                                style: GoogleFonts.cairo(
                                  fontSize: 9,
                                  color: AppColors.textHint,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, _) {
                        return Text(
                          value.toInt().toString(),
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            color: AppColors.textHint,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: chartMax > 5 ? (chartMax / 5) : 1,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(buckets.length, (i) {
                  final isTouched = i == _touchedBarIndex;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: buckets[i].toDouble(),
                        gradient: LinearGradient(
                          colors: [colors[i], colors[i].withValues(alpha: 0.6)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        width: isTouched ? 32 : 26,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: chartMax,
                          color: Colors.grey.shade100,
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopStudentsCard(
    List<Student> students,
    List<GradeField> fields,
    ClassStats stats,
  ) {
    // إصلاح: استثناء الطلاب الذين لم تُسجَّل لهم أي درجة بعد من الترتيب،
    // وإلا تظهر "أفضل 5 طلاب" وهي تضم طلاباً بصفر درجة فعلياً لمجرد
    // اكتمال العدد، وهو أمر مربك جداً أثناء تصحيح الدرجات جزئياً.
    final graded = students.where((s) => s.grades.isNotEmpty).toList();
    final sorted = [...graded]
      ..sort((a, b) => b.totalFor(fields).compareTo(a.totalFor(fields)));
    final top5 = sorted.take(5).toList();

    if (top5.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: Text(
            'لم تُسجَّل درجات بعد لعرض الترتيب',
            style: GoogleFonts.cairo(color: AppColors.textHint),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFFFFA000),
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'أعلى 5 طلاب',
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(top5.length, (i) {
            final s = top5[i];
            final studentTotal = s.totalFor(fields);
            final pct = stats.totalPossible > 0
                ? (studentTotal / stats.totalPossible) * 100
                : 0.0;
            final medalColors = [
              const Color(0xFFFFD700), // gold
              const Color(0xFFC0C0C0), // silver
              const Color(0xFFCD7F32), // bronze
              AppColors.primary,
              AppColors.info,
            ];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: medalColors[i].withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: i < 3
                          ? Icon(
                              i == 0
                                  ? Icons.workspace_premium_rounded
                                  : Icons.military_tech_rounded,
                              color: medalColors[i],
                              size: 20,
                            )
                          : Text(
                              '${i + 1}',
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: medalColors[i],
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          s.name,
                          textAlign: TextAlign.right,
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        LinearPercentIndicator(
                          padding: EdgeInsets.zero,
                          lineHeight: 6,
                          percent: (pct / 100).clamp(0.0, 1.0),
                          backgroundColor: Colors.grey.shade200,
                          progressColor: pct >= 70
                              ? AppColors.success
                              : pct >= 50
                              ? AppColors.warning
                              : AppColors.error,
                          barRadius: const Radius.circular(3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _fmt(studentTotal),
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFieldAnalysisCard(
    List<Student> students,
    List<GradeField> fields,
  ) {
    if (fields.isEmpty) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.assessment_rounded,
                color: AppColors.info,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'متوسط كل بند تقييم',
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...fields.map((f) {
            // Calculate average for this field
            double sum = 0;
            int count = 0;
            for (final s in students) {
              final v = s.grades[f.name];
              if (v != null) {
                sum += v;
                count++;
              }
            }
            final avg = count > 0 ? sum / count : 0.0;
            final pct = f.max > 0 ? (avg / f.max) : 0.0;
            final color = pct >= 0.7
                ? AppColors.success
                : pct >= 0.5
                ? AppColors.warning
                : AppColors.error;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Text(
                        '${avg.toStringAsFixed(1)} / ${_fmt(f.max)}',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        f.label,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearPercentIndicator(
                    padding: EdgeInsets.zero,
                    lineHeight: 8,
                    percent: pct.clamp(0.0, 1.0),
                    backgroundColor: Colors.grey.shade200,
                    linearGradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.6)],
                    ),
                    barRadius: const Radius.circular(4),
                    trailing: Text(
                      ' ${(pct * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPassFailPie(
    List<Student> students,
    List<GradeField> fields,
    ClassStats stats,
  ) {
    if (stats.totalPossible == 0) return const SizedBox();

    final passed = students
        .where(
          (s) =>
              s.grades.isNotEmpty &&
              s.totalFor(fields) >= stats.totalPossible * 0.5,
        )
        .length;
    final failed = students
        .where(
          (s) =>
              s.grades.isNotEmpty &&
              s.totalFor(fields) < stats.totalPossible * 0.5,
        )
        .length;
    final notGraded = students.length - passed - failed;

    if (passed + failed == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: Text(
            'لم تُسجَّل درجات بعد',
            style: GoogleFonts.cairo(color: AppColors.textHint),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pie_chart_rounded,
                color: AppColors.success,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'النجاح والرسوب',
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 160,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 40,
                      sections: [
                        if (passed > 0)
                          PieChartSectionData(
                            value: passed.toDouble(),
                            color: AppColors.success,
                            title: '$passed',
                            radius: 50,
                            titleStyle: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        if (failed > 0)
                          PieChartSectionData(
                            value: failed.toDouble(),
                            color: AppColors.error,
                            title: '$failed',
                            radius: 50,
                            titleStyle: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        if (notGraded > 0)
                          PieChartSectionData(
                            value: notGraded.toDouble(),
                            color: AppColors.textHint,
                            title: '$notGraded',
                            radius: 50,
                            titleStyle: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _pieLegend('ناجح', AppColors.success, passed),
                    const SizedBox(height: 10),
                    _pieLegend('راسب', AppColors.error, failed),
                    const SizedBox(height: 10),
                    _pieLegend('بدون درجة', AppColors.textHint, notGraded),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pieLegend(String label, Color color, int count) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '$count طالب',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}
