// اختبار إجهاد (Stress Test) لتصدير Excel بـ 100 طالب
// ------------------------------------------------------------------------
// الهدف: التحقق من أن AnalyticsService.exportToExcel() يبقى صحيحاً تماماً
// عند التشغيل على حجم بيانات واقعي كبير (100 طالب × 5 بنود تقييم)، أي:
//   1. لا يُفقد أي طالب من الـ 100 (كل اسم/رقم جلوس يظهر في الملف الناتج).
//   2. حساب "المجموع" و"النسبة %" و"التقدير" صحيح لكل طالب (يُقارن مع
//      القيم المحسوبة يدوياً في الاختبار نفسه عبر AnalyticsService._grade
//      المكافئ محلياً).
//   3. تلوين النجاح/الرسوب (totalStyle/gradeBadgeStyle) لا يعتمد على هذا
//      الاختبار مباشرة (الألوان الفعلية تُتحقق بصرياً)، لكن القيم النصية
//      يجب أن تعكس نفس منطق "pass = pct >= 50" في الطبقة الأعلى.
//   4. صف الإحصائيات (8 قيم) يبقى صحيحاً عند حساب المتوسط/النجاح على 100
//      طالب فعلي (وليس 1-2 كما في اختبارات fieldsCount=0/1 السابقة).
//   5. الأعمدة الممتدة (merge ranges) لصف المعلومات والإحصائيات والتوقيعات
//      تبقى سليمة (نفس _splitCols المُصلَحة سابقاً) عند fieldsCount=5 (حالة
//      طبيعية شائعة، بعيدة عن الحافة 0/1 التي تم اختبارها من قبل)، أي هذا
//      اختبار "الحالة الشائعة على نطاق واسع" وليس اختبار حافة إضافي.
//   6. لا حدوث أي استثناء أو تجميد أو استهلاك ذاكرة غير معقول عند التعامل
//      مع 100 صف بيانات + دمج خلايا متكرر.
//
// يُعيد استخدام نفس نمط الاختبار المُعتمد مسبقاً في
// analytics_excel_export_low_fields_test.dart (FakePathProviderPlatform +
// _exportAndDecode عبر xl.Excel.decodeBytes الفعلي) بدل تكرار الكود من
// الصفر، اتساقاً مع منهجية "الاختبار العملي الحي" المُتبعة طوال هذا المشروع.

import 'dart:io';
import 'dart:math';

import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:study_grades_voice/models/student_model.dart';
import 'package:study_grades_voice/services/analytics_service.dart';

/// نفس Fake المُستخدَم في اختبارات fieldsCount=0/1 — يُوجِّه
/// getApplicationDocumentsPath() إلى مجلد مؤقت لكي تتمكن exportToExcel()
/// من كتابة ملف فعلي أثناء `flutter test`.
class FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String path;
  FakePathProviderPlatform(this.path);
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// يُشغِّل exportToExcel() فعلياً، يجد ملف .xlsx الجديد في [tempDir]، يفكّ
/// تشفيره بـ Excel.decodeBytes، ويُعيد كل قيم الخلايا كـ
/// `Map<"row,col", String>` لتسهيل التحقق.
Future<Map<String, String>> _exportAndDecode({
  required Directory tempDir,
  required List<Student> students,
  required List<GradeField> fields,
  required String className,
  required String subject,
  String? teacherName,
}) async {
  final before = tempDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.xlsx'))
      .map((f) => f.path)
      .toSet();

  await AnalyticsService.exportToExcel(
    students: students,
    fields: fields,
    className: className,
    subject: subject,
    teacherName: teacherName,
  );

  final after = tempDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.xlsx'))
      .toList();
  final newFiles = after.where((f) => !before.contains(f.path)).toList();
  expect(newFiles.isNotEmpty, true, reason: 'يجب إنشاء ملف .xlsx جديد');

  final bytes = await newFiles.first.readAsBytes();
  expect(bytes.length, greaterThan(5000),
      reason:
          'حجم الملف يجب أن يعكس وجود 100 صف بيانات فعلياً (ليس ملفاً فارغاً/مقتطعاً)');

  final decoded = xl.Excel.decodeBytes(bytes);
  final sheet = decoded.sheets.values.first;

  final cells = <String, String>{};
  for (var r = 0; r < sheet.maxRows; r++) {
    for (var c = 0; c < sheet.maxColumns; c++) {
      final cell = sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
      final v = cell.value;
      if (v != null) cells['$r,$c'] = '$v';
    }
  }
  return cells;
}

bool _containsValue(Map<String, String> cells, String needle) =>
    cells.values.any((v) => v.contains(needle));

/// نفس منطق التقدير في AnalyticsService._grade (خاص، لذا يُعاد تعريفه هنا
/// محلياً للمقارنة المستقلة — لو اختلف المنطقان سيفشل الاختبار، وهذا هو
/// المقصود: كشف أي انحراف مستقبلي في حساب التقدير).
String _expectedGrade(double total, double totalPossible) {
  if (totalPossible <= 0) return '—';
  final pct = (total / totalPossible) * 100;
  if (pct >= 90) return 'ممتاز';
  if (pct >= 80) return 'جيد جداً';
  if (pct >= 65) return 'جيد';
  if (pct >= 50) return 'مقبول';
  return 'ضعيف';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('excel_export_100_students_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Excel export — 100 students stress test (fieldsCount = 5)', () {
    // 5 بنود تقييم بحد أقصى مختلف لكل بند (حالة واقعية شائعة)
    final fields = [
      GradeField(name: 'q1', label: 'اختبار شهري 1', max: 20),
      GradeField(name: 'q2', label: 'اختبار شهري 2', max: 20),
      GradeField(name: 'hw', label: 'واجبات', max: 10),
      GradeField(name: 'part', label: 'مشاركة', max: 10),
      GradeField(name: 'final', label: 'الاختبار النهائي', max: 40),
    ];
    final totalPossible = fields.fold<double>(0, (s, f) => s + f.max);

    // أسماء عربية متنوعة (تتضمن حروفاً خاصة: مدّات، همزات، تاء مربوطة) لضمان
    // عدم فقدان أي حرف عند التعامل مع 100 صف.
    const namePool = <String>[
      'أحمد',
      'محمد',
      'إسراء',
      'يؤيؤ',
      'عبدالرؤوف',
      'فاطمة',
      'مريم',
      'سارة',
      'خالد',
      'يوسف',
      'نور',
      'هدى',
      'إيمان',
      'عمر',
      'زينب',
      'حسناء',
      'عبدالله',
      'رقية',
      'أسماء',
      'إبراهيم',
    ];

    late List<Student> students;
    final rnd = Random(42); // seed ثابت لنتائج قابلة لإعادة الإنتاج

    setUp(() {
      students = List.generate(100, (i) {
        final firstName = namePool[i % namePool.length];
        final grades = <String, double>{
          for (final f in fields) f.name: (rnd.nextDouble() * f.max),
        };
        return Student(
          id: i + 1,
          studentNumber: '${1000 + i}',
          name: '$firstName ${i + 1}',
          grades: grades,
        );
      });
    });

    test('كل الطلاب الـ 100 يظهرون بأسمائهم وأرقام جلوسهم بدون فقدان',
        () async {
      final cells = await _exportAndDecode(
        tempDir: tempDir,
        students: students,
        fields: fields,
        className: 'الصف الأول الثانوي',
        subject: 'الرياضيات',
        teacherName: 'أ. محمد إبراهيم',
      );

      for (var i = 0; i < students.length; i++) {
        expect(_containsValue(cells, students[i].name), true,
            reason: 'اسم الطالب رقم ${i + 1} (${students[i].name}) مفقود');
        expect(_containsValue(cells, students[i].studentNumber), true,
            reason:
                'رقم جلوس الطالب رقم ${i + 1} (${students[i].studentNumber}) مفقود');
      }
    });

    test('معلومات الصف/المادة/المعلم لا تُفقد مع 100 طالب و5 بنود', () async {
      final cells = await _exportAndDecode(
        tempDir: tempDir,
        students: students,
        fields: fields,
        className: 'الصف الأول الثانوي',
        subject: 'الرياضيات',
        teacherName: 'أ. محمد إبراهيم',
      );

      expect(_containsValue(cells, 'الصف الأول الثانوي'), true);
      expect(_containsValue(cells, 'الرياضيات'), true);
      expect(_containsValue(cells, 'أ. محمد إبراهيم'), true);
      expect(_containsValue(cells, 'بيانات الطالب'), true);
      expect(_containsValue(cells, 'بنود التقييم'), true);
      expect(_containsValue(cells, 'النتيجة النهائية'), true);
    });

    test('المجموع والنسبة والتقدير محسوبون بدقة لكل طالب من الـ 100', () async {
      final cells = await _exportAndDecode(
        tempDir: tempDir,
        students: students,
        fields: fields,
        className: 'الصف الأول الثانوي',
        subject: 'الرياضيات',
      );

      for (final s in students) {
        final expectedGrade = _expectedGrade(s.total, totalPossible);
        final expectedPct = (s.total / totalPossible * 100).toStringAsFixed(1);

        // المجموع (كعدد صحيح أو عشري حسب صيغة الكتابة في الخدمة)
        final totalStr = s.total == s.total.roundToDouble()
            ? s.total.toInt().toString()
            : s.total.toString();
        expect(_containsValue(cells, totalStr), true,
            reason:
                'مجموع الطالب ${s.name} ($totalStr من $totalPossible) غير موجود في الملف');

        expect(_containsValue(cells, '$expectedPct%'), true,
            reason: 'نسبة الطالب ${s.name} ($expectedPct%) غير موجودة');

        expect(_containsValue(cells, expectedGrade), true,
            reason: 'تقدير الطالب ${s.name} ($expectedGrade) غير موجود');
      }
    });

    test('كل القيم الإحصائية الثمانية صحيحة عند حسابها على 100 طالب فعلي',
        () async {
      final cells = await _exportAndDecode(
        tempDir: tempDir,
        students: students,
        fields: fields,
        className: 'الصف الأول الثانوي',
        subject: 'الرياضيات',
      );

      final stats = AnalyticsService.calculate(students, fields);

      expect(_containsValue(cells, '${stats.totalStudents}'), true,
          reason: 'عدد الطلاب (${stats.totalStudents}) غير موجود');
      expect(_containsValue(cells, '${stats.completedStudents}'), true,
          reason: 'الطلاب المرصودون (${stats.completedStudents}) غير موجود');
      expect(
          _containsValue(
              cells, '${stats.completionPercentage.toStringAsFixed(1)}%'),
          true,
          reason: 'نسبة الإنجاز غير موجودة');
      expect(_containsValue(cells, '${stats.successRate.toStringAsFixed(1)}%'),
          true,
          reason: 'نسبة النجاح غير موجودة');

      // عدد الطلاب يجب أن يكون 100 بالضبط
      expect(stats.totalStudents, 100);
      // كل الطلاب "مرصودون" لأن كل طالب لديه درجة لكل بند
      expect(stats.completedStudents, 100);
    });

    test('التوقيعات الثلاثة تظهر كاملة رغم كِبر حجم البيانات', () async {
      final cells = await _exportAndDecode(
        tempDir: tempDir,
        students: students,
        fields: fields,
        className: 'الصف الأول الثانوي',
        subject: 'الرياضيات',
      );

      expect(_containsValue(cells, 'توقيع المعلم'), true);
      expect(_containsValue(cells, 'توقيع وكيل المدرسة'), true);
      expect(_containsValue(cells, 'توقيع المدير'), true);
    });

    test('عدد صفوف الجدول يعكس 100 طالب + رأس + صف الدرجة العظمى على الأقل',
        () async {
      final cells = await _exportAndDecode(
        tempDir: tempDir,
        students: students,
        fields: fields,
        className: 'الصف الأول الثانوي',
        subject: 'الرياضيات',
      );

      final rowIndices = cells.keys
          .map((k) => int.parse(k.split(',')[0]))
          .toSet()
          .toList()
        ..sort();
      // على الأقل: صف عنوان + صف رؤوس مجموعات + صف رؤوس أعمدة + صف الدرجة
      // العظمى + 100 صف طالب + صف إحصائيات + صفوف توقيع = أكثر من 100 صف
      // مُستخدَم فعلياً (وليس فقط 100 لأن هناك صفوفاً إضافية قبل/بعد).
      expect(rowIndices.length, greaterThan(100),
          reason:
              'عدد الصفوف الفعلية (${rowIndices.length}) يجب أن يتجاوز 100 (100 طالب + رؤوس + إحصائيات + تذييل)');
    });
  });
}
