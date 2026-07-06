import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/student_model.dart';
import '../services/admin_service.dart';
import '../services/analytics_service.dart';
import '../utils/error_handler.dart';

/// خدمة تصدير "كشف رصد الدرجات" الرسمي بصيغة PDF — نسخة موازية ومكمّلة
/// لتصدير Excel (AnalyticsService.exportToExcel)، وتعمل على *جميع* المنصات
/// بما فيها الويب (بعكس Excel الذي يتطلب dart:io على الأجهزة المحمولة
/// ويتحول تلقائياً إلى CSV على الويب).
///
/// لماذا حزمتا `pdf` + `printing`؟
///   - `pdf`: بناء المستند (صفحات/جداول/خطوط/ألوان) بشكل مستقل عن المنصة
///     بالكامل (pure-Dart)، فهو يعمل فعلياً على Web/Android/iOS/Desktop
///     دون أي فرع خاص بالمنصة.
///   - `printing`: طبقة الحفظ/المشاركة/الطباعة الجاهزة عبر المنصات —
///     توفر `Printing.sharePdf()` الذي يعمل على الموبايل (مشاركة عبر
///     share sheet) والويب (تنزيل الملف مباشرة في المتصفح) بنفس الاستدعاء
///     دون فرع `if (kIsWeb)` يدوي، على عكس excel/share_plus التي تطلبت
///     ذلك التفريع صراحةً.
///
/// دعم اللغة العربية (RTL + Cairo font):
///   - يُحمَّل الخطان Cairo-Regular / Cairo-Bold من `assets/fonts/` (نفس
///     الخط المستخدم في واجهة التطبيق) ليُضمَّنا داخل ملف الـ PDF نفسه؛
///     بدون هذا التضمين، تظهر النصوص العربية كمربعات فارغة (tofu) لأن
///     الخطوط الافتراضية في حزمة `pdf` لا تدعم العربية.
///   - `pw.TextDirection.rtl` يُمرَّر لكل صفحة/جدول لضمان الاتجاه الصحيح
///     من اليمين لليسار للنصوص والأعمدة العربية.
class PdfExportService {
  PdfExportService._();

  static pw.Font? _regularFont;
  static pw.Font? _boldFont;

  static Future<void> _ensureFontsLoaded() async {
    if (_regularFont != null && _boldFont != null) return;
    try {
      final regularData =
          await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      _regularFont = pw.Font.ttf(regularData);
      _boldFont = pw.Font.ttf(boldData);
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'PdfExportService._ensureFontsLoaded');
      rethrow;
    }
  }

  /// حساب التقدير النصي — يُعاد استخدام نفس منطق AnalyticsService عبر دالة
  /// عامة مصغّرة كي لا نُكرر قواعد الأعمدة (٩٠٪ ممتاز، ٨٠٪ جيد جداً، إلخ).
  static String _grade(double total, double totalPossible) {
    if (totalPossible <= 0) return '—';
    final pct = (total / totalPossible) * 100;
    if (pct >= 90) return 'ممتاز';
    if (pct >= 80) return 'جيد جداً';
    if (pct >= 65) return 'جيد';
    if (pct >= 50) return 'مقبول';
    return 'ضعيف';
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  /// يبني ملف PDF كامل لكشف رصد الدرجات ثم يعرضه للمستخدم عبر
  /// `Printing.sharePdf()` (مشاركة على الموبايل، تنزيل مباشر على الويب).
  ///
  /// يُعيد `true` عند النجاح و`false` عند أي خطأ (مع تسجيله في
  /// [ErrorHandler] كما هو معمول به في بقية طرق التصدير).
  static Future<bool> exportToPdf({
    required List<Student> students,
    required List<GradeField> fields,
    required String className,
    required String subject,
    String? teacherName,
    String? schoolName,
  }) async {
    try {
      await _ensureFontsLoaded();
      final regular = _regularFont!;
      final bold = _boldFont!;

      final doc = pw.Document();
      final totalPossible = fields.fold<double>(0, (s, f) => s + f.max);
      final stats = AnalyticsService.calculate(students, fields);
      final now = DateTime.now();
      final dateStr = '${now.year}/${now.month.toString().padLeft(2, '0')}/'
          '${now.day.toString().padLeft(2, '0')}';

      const primaryColor = PdfColor.fromInt(0xFF1F4E78);
      const secondaryColor = PdfColor.fromInt(0xFF2E75B6);
      const headerColor = PdfColor.fromInt(0xFF305496);
      const zebraColor = PdfColor.fromInt(0xFFF2F2F2);
      const successColor = PdfColor.fromInt(0xFF0B5394);
      const failColor = PdfColor.fromInt(0xFF9C0006);
      const statsBg = PdfColor.fromInt(0xFFFFF2CC);
      const statsFg = PdfColor.fromInt(0xFF7F6000);

      // فهارس أعمدة النتيجة النهائية (تُستخدم لاحقاً لتلوين خلايا
      // المجموع/النسبة/التقدير حسب النجاح والرسوب) — نفس تخطيط الأعمدة
      // المستخدم في AnalyticsService.exportToExcel:
      //   0: م، 1: الاسم، 2: رقم الجلوس، 3..(3+fieldsCount-1): بنود التقييم
      final fieldsCount = fields.length;
      final totalCol = 3 + fieldsCount;
      final pctCol = 3 + fieldsCount + 1;
      final gradeCol = 3 + fieldsCount + 2;

      // رؤوس الأعمدة: م، الاسم، رقم الجلوس، [بنود التقييم]، المجموع، النسبة، التقدير
      final headers = <String>[
        'م',
        'اسم الطالب',
        'رقم الجلوس',
        ...fields.map((f) => '${f.label}\n(من ${_fmt(f.max)})'),
        'المجموع\n(من ${_fmt(totalPossible)})',
        'النسبة %',
        'التقدير',
      ];

      // بناء صفوف بيانات الطلاب
      final dataRows = <List<String>>[];
      for (var i = 0; i < students.length; i++) {
        final s = students[i];
        final pct = totalPossible > 0 ? (s.total / totalPossible) * 100 : 0.0;
        final grade = _grade(s.total, totalPossible);
        dataRows.add([
          '${i + 1}',
          s.name,
          s.studentNumber,
          ...fields.map((f) {
            final v = s.grades[f.name];
            return v == null ? '' : _fmt(v);
          }),
          _fmt(s.total),
          '${pct.toStringAsFixed(1)}%',
          grade,
        ]);
      }

      pw.TextStyle style({
        double size = 10,
        PdfColor color = PdfColors.black,
        bool isBold = false,
      }) =>
          pw.TextStyle(
            font: isBold ? bold : regular,
            fontSize: size,
            color: color,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          );

      // نُقسّم الطلاب إلى صفحات (Chunks) لتفادي فيضان الذاكرة/الأداء مع
      // فصول كبيرة جداً — MultiPage من حزمة pdf تتكفل أصلاً بتقسيم الجدول
      // تلقائياً عبر الصفحات، فلا حاجة لتقسيم يدوي هنا.
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(20),
          header: (context) {
            if (context.pageNumber > 1) {
              return pw.Container(
                alignment: pw.Alignment.centerRight,
                margin: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  '$className — $subject (تابع)',
                  style: style(size: 11, isBold: true, color: primaryColor),
                  textDirection: pw.TextDirection.rtl,
                ),
              );
            }
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 10),
                  decoration: const pw.BoxDecoration(color: primaryColor),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    schoolName ?? 'كشف رصد الدرجات الرسمي',
                    style:
                        style(size: 18, isBold: true, color: PdfColors.white),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6),
                  decoration: const pw.BoxDecoration(color: secondaryColor),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    '${AdminService.appName} - ${AdminService.appNameAr}',
                    style:
                        style(size: 11, isBold: true, color: PdfColors.white),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  children: [
                    _infoChip('الصف الدراسي', className, style),
                    _infoChip('المادة', subject, style),
                    _infoChip('المعلم', teacherName ?? '—', style),
                    _infoChip('تاريخ الرصد', dateStr, style),
                  ],
                ),
                pw.SizedBox(height: 12),
              ],
            );
          },
          footer: (context) => pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              'صفحة ${context.pageNumber} من ${context.pagesCount}',
              style: style(size: 9, color: PdfColors.grey600),
              textDirection: pw.TextDirection.rtl,
            ),
          ),
          build: (context) => [
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: dataRows,
              headerStyle: style(size: 9, isBold: true, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: headerColor),
              headerDirection: pw.TextDirection.rtl,
              tableDirection: pw.TextDirection.rtl,
              cellStyle: style(size: 9),
              cellAlignment: pw.Alignment.center,
              headerAlignment: pw.Alignment.center,
              cellAlignments: {
                1: pw.Alignment.centerRight, // اسم الطالب محاذاة يمين
              },
              // تلوين خلايا "المجموع/النسبة/التقدير" حسب النجاح/الرسوب —
              // نفس منطق الألوان المستخدم في تصدير Excel (successColor
              // للناجحين، failColor للراسبين)، عبر textStyleBuilder الذي
              // يستقبل رقم العمود وقيمة الخلية النصية لكل صف على حدة.
              textStyleBuilder: (index, cellData, rowNum) {
                final isResultCol =
                    index == totalCol || index == pctCol || index == gradeCol;
                if (!isResultCol || rowNum == 0) return null;
                final studentIdx = rowNum - 1;
                if (studentIdx < 0 || studentIdx >= students.length) {
                  return null;
                }
                final s = students[studentIdx];
                final pass = totalPossible > 0
                    ? (s.total / totalPossible) >= 0.5
                    : false;
                return style(
                  size: 9,
                  isBold: true,
                  color: pass ? successColor : failColor,
                );
              },
              rowDecoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                ),
              ),
              oddRowDecoration: const pw.BoxDecoration(color: zebraColor),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 6,
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              decoration: const pw.BoxDecoration(color: secondaryColor),
              alignment: pw.Alignment.center,
              child: pw.Text(
                // ملاحظة: تم حذف الإيموجي "📊" هنا عمداً (بعكس نص الواجهة
                // في grading_screen.dart) لأن خط Cairo المُضمَّن داخل
                // ملف الـ PDF لا يحتوي على رموز الرموز التعبيرية
                // (Unicode Emoji)، مما يُسبب تحذير "Unable to find a font
                // to draw" ويُظهر مربعاً فارغاً (tofu) بدل الرمز في
                // المستند الناتج. واجهة Flutter نفسها تعرض الإيموجي بشكل
                // سليم لأنها تعتمد على خطوط الرموز التعبيرية للنظام
                // (Noto Color Emoji) والتي لا تُضمَّن هنا.
                'الإحصائيات العامة للفصل',
                style: style(size: 12, isBold: true, color: PdfColors.white),
                textDirection: pw.TextDirection.rtl,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statBox('عدد الطلاب', '${stats.totalStudents}', style, statsBg,
                    statsFg),
                _statBox('الطلاب المرصودون', '${stats.completedStudents}',
                    style, statsBg, statsFg),
                _statBox(
                    'نسبة الإنجاز',
                    '${stats.completionPercentage.toStringAsFixed(1)}%',
                    style,
                    statsBg,
                    statsFg),
                _statBox('المتوسط العام', _fmt(stats.averageScore), style,
                    statsBg, statsFg),
                _statBox(
                    'نسبة النجاح',
                    '${stats.successRate.toStringAsFixed(1)}%',
                    style,
                    statsBg,
                    statsFg),
                _statBox('أعلى درجة', _fmt(stats.highestScore), style, statsBg,
                    statsFg),
                _statBox('أقل درجة', _fmt(stats.lowestScore), style, statsBg,
                    statsFg),
                _statBox('الدرجة الكلية', _fmt(stats.totalPossible), style,
                    statsBg, statsFg),
              ],
            ),
            pw.SizedBox(height: 30),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _signatureBlock('توقيع المعلم', style),
                _signatureBlock('توقيع وكيل المدرسة', style),
                _signatureBlock('توقيع المدير', style),
              ],
            ),
          ],
        ),
      );

      final bytes = await doc.save();
      final fileName =
          'كشف_درجات_${_safeName(className)}_${_safeName(subject)}_'
          '${DateTime.now().millisecondsSinceEpoch}.pdf';

      // Printing.sharePdf يعمل بشكل موحّد عبر جميع المنصات: على الموبايل
      // يفتح قائمة المشاركة (Share Sheet)، وعلى الويب يُنزِّل الملف مباشرة
      // في المتصفح — بدون أي فرع `if (kIsWeb)` يدوي (بعكس Excel/CSV).
      await Printing.sharePdf(bytes: bytes, filename: fileName);
      return true;
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'PdfExportService.exportToPdf');
      return false;
    }
  }

  static pw.Widget _infoChip(
    String label,
    String value,
    pw.TextStyle Function({double size, PdfColor color, bool isBold}) style,
  ) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 3),
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFD9E1F2),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              label,
              style: style(
                  size: 9,
                  isBold: true,
                  color: const PdfColor.fromInt(0xFF1F4E78)),
              textDirection: pw.TextDirection.rtl,
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              value,
              style: style(size: 10),
              textDirection: pw.TextDirection.rtl,
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _statBox(
    String label,
    String value,
    pw.TextStyle Function({double size, PdfColor color, bool isBold}) style,
    PdfColor bg,
    PdfColor fg,
  ) {
    return pw.Container(
      width: 130,
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: fg, width: 0.5),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            label,
            style: style(size: 9, isBold: true, color: fg),
            textDirection: pw.TextDirection.rtl,
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: style(size: 11, isBold: true, color: fg),
            textDirection: pw.TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  static pw.Widget _signatureBlock(
    String label,
    pw.TextStyle Function({double size, PdfColor color, bool isBold}) style,
  ) {
    return pw.Column(
      children: [
        pw.Container(
          width: 140,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.7),
            ),
          ),
          padding: const pw.EdgeInsets.only(bottom: 20),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          label,
          style: style(size: 10, isBold: true),
          textDirection: pw.TextDirection.rtl,
        ),
      ],
    );
  }

  static String _safeName(String input) {
    return input.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
  }
}
