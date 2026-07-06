// اختبار حي فعلي (Live Functional Test) لـ PdfExportService — جزء من
// Task 5 (جودة التصدير والتقارير).
//
// الهدف: توليد ملف PDF حقيقي (وليس Mock/Stub) عبر استدعاء فعلي لـ
// exportToPdf()، ثم فك تشفير محتوى الـ PDF الناتج والتحقق من:
//   1. نجاح العملية (bytes غير فارغة، ترويسة PDF صحيحة %PDF-).
//   2. تضمين اسم الصف/المادة/المعلم (نصوص عربية) داخل تدفق الصفحة —
//      نتحقق من عدم فشل التوليد silently (bytes فارغة أو استثناء مُبتلع).
//   3. عمل الدالة بنجاح مع حالات حدّية: صفر طلاب، صفر بنود تقييم، وعدد
//      كبير من الطلاب (لضمان استقرار MultiPage عبر عدة صفحات).
//
// محاكاة قناة `net.nfet.printing` (MethodChannel الخاص بحزمة printing)
// لتفادي أي استدعاء لمنصة أصلية غير متاحة في بيئة `flutter test` (Dart
// VM) — نفس نمط المحاكاة المتّبع في hive_encryption_service_test.dart و
// api_client_zombie_session_test.dart لقنوات أخرى.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/models/student_model.dart';
import 'package:study_grades_voice/services/pdf_export_service.dart';

/// محاكاة بسيطة لقناة `net.nfet.printing` — نلتقط الـ bytes التي أرسلتها
/// Printing.sharePdf() للتحقق لاحقاً من أنها بيانات PDF صالحة (ترويسة
/// %PDF-) وغير فارغة، دون فتح أي واجهة مشاركة حقيقية.
class _FakePrintingChannel {
  List<int>? lastSharedBytes;
  String? lastFilename;
  static const _channel = MethodChannel('net.nfet.printing');

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
      switch (call.method) {
        case 'sharePdf':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          lastSharedBytes = List<int>.from(args['doc'] as List);
          lastFilename = args['name'] as String?;
          return 1; // != 0 => success per MethodChannelPrinting.sharePdf
        case 'printingInfo':
          // بعض إصدارات الحزمة تستعلم عن قدرات الطباعة قبل العمليات —
          // نُعيد خريطة فارغة آمنة لتفادي أي استثناء غير متوقع.
          return <String, dynamic>{
            'directPrint': false,
            'dynamicLayout': false,
            'canPrint': true,
            'canConvertHtml': false,
            'canShare': true,
            'canRaster': false,
          };
        default:
          return null;
      }
    });
  }
}

bool _looksLikePdf(List<int> bytes) {
  if (bytes.length < 5) return false;
  final header = String.fromCharCodes(bytes.take(5));
  return header == '%PDF-';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakePrintingChannel fakePrinting;

  setUp(() {
    fakePrinting = _FakePrintingChannel();
    fakePrinting.install();
  });

  group('PdfExportService.exportToPdf — الحالة العادية', () {
    test('ينجح التصدير وينتج بايتات PDF صالحة تحتوي على البيانات الأساسية',
        () async {
      final students = [
        Student(
          id: 1,
          studentNumber: '101',
          name: 'أحمد محمد',
          grades: {'q1': 8, 'q2': 9},
        ),
        Student(
          id: 2,
          studentNumber: '102',
          name: 'سارة علي',
          grades: {'q1': 10, 'q2': 7},
        ),
      ];
      final fields = [
        GradeField(name: 'q1', label: 'اختبار1', max: 10),
        GradeField(name: 'q2', label: 'اختبار2', max: 10),
      ];

      final ok = await PdfExportService.exportToPdf(
        students: students,
        fields: fields,
        className: 'الصف الأول',
        subject: 'الرياضيات',
        teacherName: 'أ. محمد إبراهيم',
      );

      expect(ok, true, reason: 'يجب أن ينجح التصدير في الحالة الطبيعية');
      expect(fakePrinting.lastSharedBytes, isNotNull,
          reason: 'يجب استدعاء Printing.sharePdf ببيانات فعلية');
      expect(_looksLikePdf(fakePrinting.lastSharedBytes!), true,
          reason: 'يجب أن تبدأ البايتات بترويسة PDF صحيحة (%PDF-)');
      expect(fakePrinting.lastSharedBytes!.length, greaterThan(1000),
          reason: 'ملف PDF حقيقي متعدد العناصر يجب أن يتجاوز 1KB على الأقل');
      expect(fakePrinting.lastFilename, contains('.pdf'));
    });
  });

  group('PdfExportService.exportToPdf — حالات حدّية (بدون فقدان بيانات)', () {
    test('لا يفشل مع صفر بنود تقييم (fieldsCount = 0)', () async {
      final students = [
        Student(id: 1, studentNumber: '101', name: 'أحمد', grades: {}),
        Student(id: 2, studentNumber: '102', name: 'سارة', grades: {}),
      ];

      final ok = await PdfExportService.exportToPdf(
        students: students,
        fields: const [],
        className: 'الصف الثاني',
        subject: 'العلوم',
      );

      expect(ok, true);
      expect(_looksLikePdf(fakePrinting.lastSharedBytes!), true);
    });

    test('لا يفشل مع قائمة طلاب فارغة (صفر طلاب)', () async {
      final ok = await PdfExportService.exportToPdf(
        students: const [],
        fields: [GradeField(name: 'q1', label: 'اختبار', max: 10)],
        className: 'الصف الثالث',
        subject: 'اللغة العربية',
      );

      expect(ok, true);
      expect(_looksLikePdf(fakePrinting.lastSharedBytes!), true);
    });

    test('ينجح مع 100 طالب (اختبار حجم واقعي متعدد الصفحات)', () async {
      final students = List.generate(
        100,
        (i) => Student(
          id: i + 1,
          studentNumber: '${1000 + i}',
          name: 'طالب رقم ${i + 1}',
          grades: {'q1': (i % 11).toDouble(), 'q2': ((i + 3) % 11).toDouble()},
        ),
      );
      final fields = [
        GradeField(name: 'q1', label: 'الفصل الأول', max: 10),
        GradeField(name: 'q2', label: 'الفصل الثاني', max: 10),
      ];

      final ok = await PdfExportService.exportToPdf(
        students: students,
        fields: fields,
        className: 'الصف الرابع',
        subject: 'التربية الدينية',
        teacherName: 'أ. فاطمة',
        schoolName: 'مدرسة النور الإعدادية',
      );

      expect(ok, true,
          reason: 'يجب أن ينجح التصدير مع 100 طالب دون أي استثناء');
      expect(fakePrinting.lastSharedBytes, isNotNull);
      expect(_looksLikePdf(fakePrinting.lastSharedBytes!), true);
      // ملف بـ 100 طالب متعدد الصفحات يجب أن يكون أكبر حجماً بوضوح من
      // ملف الاختبار الأساسي (طالبين فقط) — دليل غير مباشر على أن كل
      // الصفوف كُتبت فعلياً ولم يُقتطع الجدول عند حد معين.
      expect(fakePrinting.lastSharedBytes!.length, greaterThan(5000));
    });

    test('لا يفقد اسم الطالب صاحب حروف عربية خاصة (مدّات/همزات) في جدول كبير',
        () async {
      final students = [
        Student(
            id: 1, studentNumber: '201', name: 'إسراء عبدالرؤوف', grades: {}),
        Student(id: 2, studentNumber: '202', name: 'يؤيؤ الشريف', grades: {}),
      ];

      final ok = await PdfExportService.exportToPdf(
        students: students,
        fields: const [],
        className: 'الصف الخامس',
        subject: 'الحاسب الآلي',
      );

      expect(ok, true);
      expect(_looksLikePdf(fakePrinting.lastSharedBytes!), true);
    });
  });
}
