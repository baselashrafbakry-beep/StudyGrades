import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/grading_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/upgrade_required_dialog.dart';
import 'grading_screen.dart';

class SubjectSelectionScreen extends StatefulWidget {
  final int classId;
  final String className;
  const SubjectSelectionScreen({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<SubjectSelectionScreen> createState() => _SubjectSelectionScreenState();
}

class _SubjectSelectionScreenState extends State<SubjectSelectionScreen> {
  final List<_SubjectOption> _subjects = const [
    _SubjectOption('General', 'عام', Icons.book_outlined, Color(0xFF1976D2)),
    _SubjectOption(
      'Arabic',
      'اللغة العربية',
      Icons.menu_book_rounded,
      Color(0xFF8E24AA),
    ),
    _SubjectOption(
      'English',
      'اللغة الإنجليزية',
      Icons.translate_rounded,
      Color(0xFFE53935),
    ),
    _SubjectOption(
      'Math',
      'الرياضيات',
      Icons.calculate_rounded,
      Color(0xFF00897B),
    ),
    _SubjectOption(
      'Science',
      'العلوم',
      Icons.science_rounded,
      Color(0xFF43A047),
    ),
    _SubjectOption(
      'Social',
      'الدراسات الاجتماعية',
      Icons.public_rounded,
      Color(0xFFFB8C00),
    ),
    _SubjectOption(
      'Religion',
      'التربية الدينية',
      Icons.mosque_rounded,
      Color(0xFF6D4C41),
    ),
    _SubjectOption(
      'Computer',
      'الحاسب الآلي',
      Icons.computer_rounded,
      Color(0xFF3949AB),
    ),
  ];

  final TextEditingController _customCtrl = TextEditingController();
  bool _isLoading = false; // حماية من double-tap

  Future<void> _selectSubject(String subject, String displayName) async {
    if (_isLoading) return; // منع الضغط المزدوج
    setState(() => _isLoading = true);
    final grading = context.read<GradingProvider>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
    try {
      await grading.loadClassroom(
        classId: widget.classId,
        className: widget.className,
        subject: subject,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    if (!mounted) return;
    Navigator.of(context).pop();

    // فرض حد عدد الفصول (maxClassesPerTeacher): تم رفض فتح هذا الفصل
    // لأنه فصل جديد يتجاوز حد الباقة الحالية.
    if (grading.classLimitExceeded) {
      await UpgradeRequiredDialog.show(
        context,
        featureNameAr: 'فتح فصول دراسية إضافية',
        requiredPlanAr: 'أعلى',
        icon: Icons.class_rounded,
        customMessage:
            'لقد وصلت للحد الأقصى لعدد الفصول الدراسية المسموح بها في'
            ' باقتك الحالية.\nقم بالترقية لفتح فصول إضافية دون قيود.',
      );
      return;
    }

    if (grading.classroom != null && grading.classroom!.students.isNotEmpty) {
      // تنبيه غير حاجب عند قصّ قائمة الطلاب بسبب حد maxStudentsPerClass
      if (grading.trimmedStudentsCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
            content: Text(
              'باقتك الحالية تدعم عدداً محدوداً من الطلاب — تم استبعاد '
              '${grading.trimmedStudentsCount} طالب. قم بالترقية لعرض الكل.',
              style: GoogleFonts.cairo(fontSize: 13),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GradingScreen(
            classId: widget.classId,
            className: widget.className,
            subject: displayName,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          content: Text(
            grading.error ?? 'لا يوجد طلاب أو لم يتم العثور على بيانات',
            style: GoogleFonts.cairo(),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
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
                          'اختر المادة',
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
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.class_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.className,
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'المواد الدراسية',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 14),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.05,
                      ),
                      itemCount: _subjects.length,
                      itemBuilder: (_, i) {
                        final s = _subjects[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _selectSubject(s.key, s.label),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: s.color.withValues(alpha: 0.13),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(s.icon, color: s.color, size: 30),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  s.label,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.cairo(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'مادة مخصصة',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _customCtrl,
                            textAlign: TextAlign.right,
                            decoration: const InputDecoration(
                              hintText: 'اكتب اسم المادة (إنجليزي للسيرفر)',
                              prefixIcon: Icon(Icons.edit_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                final v = _customCtrl.text.trim();
                                if (v.isEmpty) return;
                                _selectSubject(v, v);
                              },
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: Text(
                                'متابعة',
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectOption {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const _SubjectOption(this.key, this.label, this.icon, this.color);
}
