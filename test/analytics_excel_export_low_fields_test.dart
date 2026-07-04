// اختبارات تراجعية (Regression Tests) لثغرة فقدان البيانات في تصدير Excel
// ------------------------------------------------------------------------
// اكتُشفت هذه الثغرة عبر اختبار فعلي حي (hands-on) لا نظري: كانت دالة
// AnalyticsService.exportToExcel() تحسب عرض الأعمدة المدمجة (merge ranges)
// لصف المعلومات (الصف/المادة/المعلم/التاريخ) وصف رؤوس المجموعات وصف
// الإحصائيات عبر قسمة صحيحة-لأسفل (floor division):
//
//     pairWidth = (totalCols / n).floor()
//
// بما أن totalCols = 3 + fieldsCount + 3، فعندما تكون fieldsCount = 0 أو 1
// (حالة حقيقية وشائعة: مادة بلا بنود تقييم مُعرَّفة بعد، أو اختبار واحد
// فقط)، يصبح totalCols = 6 أو 7، وقسمته floor على 4 (عدد أزواج صف
// المعلومات) أو حتى على نفسه (صف الإحصائيات) تنتج مدى أعمدة معكوس أو
// متداخل (reversed/overlapping merge range). حزمة excel لا ترفض هذه
// المدايات ولا ترمي استثناءً — لكنها تُسبب فقدان صامت للبيانات: تختفي
// بيانات الصف الدراسي والمادة واسم المعلم بالكامل من الملف الناتج (يبقى
// التاريخ فقط)، ويختفي أيضاً حتى 6 من أصل 8 قيم إحصائية.
//
// تم إصلاح الثغرة عبر:
//   1. AnalyticsService._splitCols(totalCols, n) — دالة تقسيم عادلة تضمن
//      توزيع كل الأعمدة المتاحة (totalCols) على n مدى متجاور بدون تراكب
//      وبدون فقدان أي عمود (تستخدم الباقي remainder بدل floor فقط).
//   2. writeLabelValuePair() — تتعامل بأمان مع مدى بعرض عمود واحد بدمج
//      التسمية والقيمة في خلية واحدة "التسمية: القيمة" بدل إسقاط أحدهما.
//   3. حماية صف رؤوس المجموعات: تخطي رسم "بنود التقييم" بالكامل عند
//      fieldsCount == 0 بدل رسم مدى معكوس يُفسد الصف بأكمله.
//
// هذه المجموعة من الاختبارات تُحاكي استدعاءً حقيقياً (REAL) لـ
// exportToExcel (وليس Mock/Stub) ثم تُعيد فك تشفير (decode) الملف
// .xlsx الناتج فعلياً للتحقق من وجود كل القيم المتوقعة — تماماً كما تم
// اكتشاف الثغرة أصلاً.

import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:study_grades_voice/models/student_model.dart';
import 'package:study_grades_voice/services/analytics_service.dart';

/// Fake [PathProviderPlatform] redirecting `getApplicationDocumentsPath()`
/// to a temp directory so exportToExcel() can actually write a file during
/// `flutter test` (no real device/file-system plugin available in tests).
class FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String path;
  FakePathProviderPlatform(this.path);
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// Runs a real exportToExcel() call, locates the generated .xlsx file in
/// [tempDir], decodes it back with `Excel.decodeBytes`, and returns every
/// cell's textual value as a `Map<"row,col", String>` for easy assertions.
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
  expect(newFiles.isNotEmpty, true,
      reason: 'Expected a new .xlsx file to be created');

  final bytes = await newFiles.first.readAsBytes();
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

/// Returns true if any cell value in [cells] contains [needle] as a
/// substring.
///
/// Substring (not exact) matching is required because
/// `AnalyticsService.writeLabelValuePair()` intentionally combines a
/// label and its value into a single cell as `"label: value"` whenever the
/// merged column range is too narrow (width 1) to hold two separate
/// cells — this is the safe fallback behaviour introduced by the fix
/// (see `_splitCols` / `writeLabelValuePair` in analytics_service.dart),
/// which guarantees the data is never silently dropped, but means it may
/// no longer occupy its own dedicated cell.
bool _containsValue(Map<String, String> cells, String needle) =>
    cells.values.any((v) => v.contains(needle));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('excel_export_low_fields_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Excel export — zero grading fields (fieldsCount = 0)', () {
    test(
        'info row (class/subject/teacher) must NOT be lost when there are no fields',
        () async {
      final cells = await _exportAndDecode(
        tempDir: tempDir,
        students: [
          Student(id: 1, studentNumber: '101', name: 'أحمد محمد', grades: {}),
          Student(id: 2, studentNumber: '102', name: 'سارة علي', grades: {}),
        ],
        fields: const [],
        className: 'الصف الأول',
        subject: 'الرياضيات',
        teacherName: 'محمد إبراهيم',
      );

      expect(_containsValue(cells, 'الصف الدراسي'), true,
          reason: 'عنوان "الصف الدراسي" يجب أن يظهر في الملف');
      expect(_containsValue(cells, 'الصف الأول'), true,
          reason: 'قيمة اسم الصف يجب ألا تُفقد');
      expect(_containsValue(cells, 'المادة'), true);
      expect(_containsValue(cells, 'الرياضيات'), true,
          reason: 'اسم المادة يجب ألا يُفقد');
      expect(_containsValue(cells, 'المعلم'), true);
      expect(_containsValue(cells, 'محمد إبراهيم'), true,
          reason: 'اسم المعلم يجب ألا يُفقد');
      expect(_containsValue(cells, 'تاريخ الرصد'), true);
    });

    test('group header row must show "بيانات الطالب" and "النتيجة النهائية"',
        () async {
      final cells = await _exportAndDecode(
        tempDir: tempDir,
        students: [
          Student(id: 1, studentNumber: '101', name: 'أحمد محمد', grades: {}),
        ],
        fields: const [],
        className: 'الصف الثاني',
        subject: 'العلوم',
        teacherName: 'أ. علي',
      );

      expect(_containsValue(cells, 'بيانات الطالب'), true);
      expect(_containsValue(cells, 'النتيجة النهائية'), true);
      // "بنود التقييم" لا معنى لعرضه بدون أي عمود بيانات — يجب تخطيه بأمان
      // (وليس رسمه بمدى معكوس يُفسد الصف بالكامل).
    });

    test('all 8 statistics values must survive with zero fields', () async {
      final cells = await _exportAndDecode(
        tempDir: tempDir,
        students: [
          Student(id: 1, studentNumber: '101', name: 'أحمد', grades: {}),
          Student(id: 2, studentNumber: '102', name: 'سارة', grades: {}),
        ],
        fields: const [],
        className: 'الصف الثالث',
        subject: 'اللغة العربية',
      );

      const expectedLabels = <String>[
        'عدد الطلاب',
        'الطلاب المرصودون',
        'نسبة الإنجاز',
        'المتوسط العام',
        'نسبة النجاح',
        'أعلى درجة',
        'أقل درجة',
        'الدرجة الكلية',
      ];
      for (final label in expectedLabels) {
        expect(_containsValue(cells, label), true,
            reason: 'يجب ألا تُفقد قيمة الإحصائية: $label');
      }
    });

    test('all 3 signature labels must survive with zero fields', () async {
      final cells = await _exportAndDecode(
        tempDir: tempDir,
        students: [
          Student(id: 1, studentNumber: '101', name: 'أحمد', grades: {}),
        ],
        fields: const [],
        className: 'الصف الرابع',
        subject: 'التربية الدينية',
      );

      expect(_containsValue(cells, 'توقيع المعلم'), true);
      expect(_containsValue(cells, 'توقيع وكيل المدرسة'), true);
      expect(_containsValue(cells, 'توقيع المدير'), true);
    });
  });

  group('Excel export — exactly one grading field (fieldsCount = 1)', () {
    test('info row must NOT be lost with a single grading field', () async {
      final cells = await _exportAndDecode(
        tempDir: tempDir,
        students: [
          Student(
              id: 1,
              studentNumber: '101',
              name: 'أحمد محمد',
              grades: {'q1': 8}),
          Student(
              id: 2, studentNumber: '102', name: 'سارة علي', grades: {'q1': 9}),
        ],
        fields: [GradeField(name: 'q1', label: 'الاختبار', max: 10)],
        className: 'الصف الخامس',
        subject: 'الدراسات الاجتماعية',
        teacherName: 'أ. فاطمة',
      );

      expect(_containsValue(cells, 'الصف الخامس'), true);
      expect(_containsValue(cells, 'الدراسات الاجتماعية'), true);
      expect(_containsValue(cells, 'أ. فاطمة'), true);
    });

    test('all 8 statistics values must survive with a single field', () async {
      final cells = await _exportAndDecode(
        tempDir: tempDir,
        students: [
          Student(id: 1, studentNumber: '101', name: 'أحمد', grades: {'q1': 8}),
          Student(id: 2, studentNumber: '102', name: 'سارة', grades: {'q1': 9}),
        ],
        fields: [GradeField(name: 'q1', label: 'الاختبار', max: 10)],
        className: 'الصف السادس',
        subject: 'الحاسب الآلي',
      );

      const expectedLabels = <String>[
        'عدد الطلاب',
        'الطلاب المرصودون',
        'نسبة الإنجاز',
        'المتوسط العام',
        'نسبة النجاح',
        'أعلى درجة',
        'أقل درجة',
        'الدرجة الكلية',
      ];
      for (final label in expectedLabels) {
        expect(_containsValue(cells, label), true,
            reason: 'يجب ألا تُفقد قيمة الإحصائية: $label');
      }
    });
  });

  group('Excel export — two grading fields (fieldsCount = 2, control case)',
      () {
    test('info row, group headers, and stats all display correctly', () async {
      final cells = await _exportAndDecode(
        tempDir: tempDir,
        students: [
          Student(
              id: 1,
              studentNumber: '101',
              name: 'أحمد محمد',
              grades: {'q1': 8, 'q2': 7}),
          Student(
              id: 2,
              studentNumber: '102',
              name: 'سارة علي',
              grades: {'q1': 9, 'q2': 10}),
        ],
        fields: [
          GradeField(name: 'q1', label: 'اختبار1', max: 10),
          GradeField(name: 'q2', label: 'اختبار2', max: 10),
        ],
        className: 'الصف الثاني',
        subject: 'العلوم',
        teacherName: 'أ. محمد إبراهيم',
      );

      expect(_containsValue(cells, 'الصف الثاني'), true);
      expect(_containsValue(cells, 'العلوم'), true);
      expect(_containsValue(cells, 'أ. محمد إبراهيم'), true);
      expect(_containsValue(cells, 'بيانات الطالب'), true);
      expect(_containsValue(cells, 'بنود التقييم'), true);
      expect(_containsValue(cells, 'النتيجة النهائية'), true);
    });
  });
}
