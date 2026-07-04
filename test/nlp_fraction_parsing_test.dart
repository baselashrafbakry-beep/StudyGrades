import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/services/nlp_parser.dart';

/// اختبارات إصلاح ثغرة أمنية حرجة في محرك تفسير الأرقام الصوتية
/// (NLPParser._extractArabicNumbers).
///
/// السياق: كانت هناك تمريرتان منفصلتان لاستخراج الأرقام من نفس الجملة —
/// تمريرة أولى (بحث عن عبارات مركّبة كنص فرعي) وتمريرة ثانية (كلمة بكلمة)
/// تُعيدان معالجة نفس الكلمات دون تنسيق بينهما. النتيجة كانت فساداً صامتاً
/// وخطيراً في بيانات الدرجات المرصودة صوتياً، مثال حقيقي مُكتشَف:
///   المعلم يقول: "عشرة وثلاثة أرباع" (يقصد الدرجة 10.75)
///   التطبيق (قبل الإصلاح) يُسجِّل: [10.0, 3.0] ← درجتان خاطئتان تماماً!
///
/// هذا الملف يوثّق ويحمي ضد جميع الحالات التي تم اكتشافها فعلياً عبر
/// اختبار حي (dart run) أثناء التدقيق الأمني الشامل.
void main() {
  group('NLPParser — إصلاح ثغرة الكسور الصوتية (Pillar 1 Critical Bug)', () {
    test('عشرة وثلاثة أرباع => 10.75 (وليس [10, 3])', () {
      final r = NLPParser.parse('عشره وثلاثه ارباع');
      expect(r.numbers, [10.75]);
    });

    test('ثمانية عشر وثلاثة أرباع => 18.75', () {
      final r = NLPParser.parse('تمنتاشر وثلاثة ارباع');
      expect(r.numbers, [18.75]);
    });

    test('خمسة عشر وثلاثة أرباع => 15.75', () {
      final r = NLPParser.parse('خمسه عشر وثلاثه ارباع');
      expect(r.numbers, [15.75]);
    });

    test('خمسة عشر ونص => 15.5', () {
      final r = NLPParser.parse('خمسه عشر ونص');
      expect(r.numbers, [15.5]);
    });

    test('عشرة وربع => 10.25', () {
      final r = NLPParser.parse('عشره وربع');
      expect(r.numbers, [10.25]);
    });

    test('تسعة وتلت => 9.333', () {
      final r = NLPParser.parse('تسعه وتلت');
      expect(r.numbers[0], closeTo(9.333, 0.001));
    });

    test('ثلاثة أرباع بدون رقم سابق => تُهمَل (لا تُسجَّل كـ 3 خطأً)', () {
      final r = NLPParser.parse('ثلاثه ارباع');
      expect(r.numbers, isEmpty);
    });

    test('كسر بعد رقم يحتوي على كسر بالفعل => يُتجاهل (منع تراكم مزدوج)', () {
      // "عشرة ونص ونص" - الكسر الثاني يجب أن يُتجاهل
      final r = NLPParser.parse('عشره ونص ونص');
      expect(r.numbers, [10.5]);
    });
  });

  group('NLPParser — إصلاح ثغرة الأعداد المركّبة (11-19)', () {
    test('أحد عشر => [11] فقط (وليس [11, 10] أو ما شابه)', () {
      expect(NLPParser.parse('احد عشر').numbers, [11]);
    });

    test('اثنا عشر => [12] فقط', () {
      expect(NLPParser.parse('اثنا عشر').numbers, [12]);
    });

    test('ثلاثة عشر => [13] فقط (وليس [13, 3, 10])', () {
      expect(NLPParser.parse('ثلاثه عشر').numbers, [13]);
    });

    test('أربعة عشر (اربعتاشر) => [14] فقط', () {
      expect(NLPParser.parse('اربعتاشر').numbers, [14]);
    });

    test('خمسة عشر => [15] فقط (وليس [15, 5, 10])', () {
      expect(NLPParser.parse('خمسه عشر').numbers, [15]);
    });

    test('ستة عشر => [16] فقط', () {
      expect(NLPParser.parse('سته عشر').numbers, [16]);
    });

    test('سبعة عشر (سبعتاشر) => [17] فقط', () {
      expect(NLPParser.parse('سبعتاشر').numbers, [17]);
    });

    test('ثمانية عشر (تمنتاشر) => [18] فقط', () {
      expect(NLPParser.parse('تمنتاشر').numbers, [18]);
    });

    test('تسعة عشر (تسعتاشر) => [19] فقط', () {
      expect(NLPParser.parse('تسعتاشر').numbers, [19]);
    });
  });

  group('NLPParser — إصلاح ثغرة فقدان القيم المتكررة الشرعية', () {
    test('عشرة عشرة => [10, 10] (درجتان منفصلتان، ليس رقماً واحداً)', () {
      // سيناريو حقيقي: معلم يرصد 10/10 لحقلين مختلفين (مثال: سلوك + مواظبة)
      final r = NLPParser.parse('عشره عشره');
      expect(r.numbers, [10, 10]);
    });

    test('خمسة خمسة => [5, 5]', () {
      expect(NLPParser.parse('خمسه خمسه').numbers, [5, 5]);
    });

    test('أرقام لاتينية متكررة => [10, 10] (تأكيد عدم التأثر بالإصلاح)', () {
      expect(NLPParser.parse('10 10').numbers, [10, 10]);
    });
  });

  group('NLPParser — تأكيد عدم كسر السلوك الصحيح الموجود مسبقاً', () {
    test('خمسة وعشرين => 25 (اتجاه: وحدة ثم عشرات)', () {
      expect(NLPParser.parse('خمسه وعشرين').numbers, [25]);
    });

    test('عشرين وخمسة => 25 (اتجاه: عشرات ثم وحدة)', () {
      expect(NLPParser.parse('عشرين وخمسه').numbers, [25]);
    });

    test('خمسة وثلاثين => 35', () {
      expect(NLPParser.parse('خمسه وثلاثين').numbers, [35]);
    });

    test('أرقام لاتينية وعشرية مختلطة تبقى تعمل', () {
      final r = NLPParser.parse('10 12.5 18');
      expect(r.numbers, containsAll([10, 12.5, 18]));
    });

    test('صفر منفردة => [0] رقم وليس أمر مسح', () {
      final r = NLPParser.parse('صفر');
      expect(r.numbers, [0]);
      expect(r.hasClear, false);
    });

    test('نص وحدها بدون رقم سابق => تُهمَل تماماً (لا تُحدث خطأ)', () {
      final r = NLPParser.parse('نص');
      expect(r.numbers, isEmpty);
    });
  });
}
