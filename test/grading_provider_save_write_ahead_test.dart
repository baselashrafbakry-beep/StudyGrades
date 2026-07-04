// اختبار حي (Live Functional Test) لإصلاح ثغرة/عطل "فقدان بيانات الحفظ"
// (Save Data-Loss Window Bug) في GradingProvider.saveCurrentStudent().
//
// 🔴 المشكلة الأصلية المُكتشَفة (Pillar 1 Edge Case c — "المستخدم يغلق
// التطبيق فجأة أثناء الحفظ"):
// كانت النسخة القديمة تكتب إلى قائمة الانتظار المحلية في Hive
// (pending_grades_box) فقط **بعد** فشل استدعاء الشبكة (داخل catch) أو في
// الفرع الأوفلاين الصريح. أثناء انتظار `await apiClient.syncGrades(...)`
// نفسه — وهو ما قد يستغرق ثوانٍ على شبكة بطيئة أو يتعلّق تماماً عند
// انقطاع الاتصال بشكل غير نظيف — كانت درجات الطالب موجودة في الذاكرة
// (RAM) فقط. فإذا أنهى نظام التشغيل عملية التطبيق فجأة (نفاد ذاكرة،
// إغلاق قسري من المستخدم، swipe-to-kill...) في هذه النافذة الزمنية
// الحرجة، كانت الدرجات تُفقَد نهائياً دون أي أثر على القرص.
//
// ✅ الإصلاح: نمط "Write-Ahead Log" — الحمولة تُكتَب إلى صندوق الانتظار
// في Hive **أولاً وقبل أي استدعاء شبكة على الإطلاق** (سطر واحد `await`
// متزامن قصير جداً على القرص المحلي، غير عرضة عملياً لنفس خطر التعليق
// الطويل لطلبات الشبكة)، ثم تُحذَف من قائمة الانتظار فقط عند نجاح
// المزامنة الفعلي عبر `removePendingSync()` الجديدة (وليس عبر
// `clearPendingSyncs()` التي كانت ستحذف عناصر أخرى معلّقة بالخطأ).
//
// هذا الملف يختبر بشكل حتمي (deterministic) وبدون أي اتصال شبكة حقيقي
// أو اعتماد على حزمة connectivity_plus (التي تحتاج MethodChannel أصلي
// غير متاح في بيئة `flutter test`)، عبر نقاط حَقن الاختبار الجديدة في
// GradingProvider: `debugSyncOverride`, `debugSetOnline`,
// `debugSetClassroom`.

import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:study_grades_voice/models/student_model.dart';
import 'package:study_grades_voice/providers/grading_provider.dart';
import 'package:study_grades_voice/services/storage_service.dart';

/// يبني فصلاً دراسياً بسيطاً بطالب واحد أو أكثر لأغراض الاختبار.
ClassroomData _buildClassroom({
  required int classId,
  List<Student>? students,
}) {
  return ClassroomData(
    classId: classId,
    className: 'فصل الاختبار',
    subject: 'رياضيات',
    fields: [
      GradeField(name: 'oral', label: 'شفهي', max: 15),
      GradeField(name: 'written', label: 'تحريري', max: 25),
    ],
    students: students ??
        [
          Student(id: 101, studentNumber: '001', name: 'طالب الاختبار'),
        ],
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_write_ahead_test_');
    Hive.init(tempDir.path);
    await StorageService.init();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('GradingProvider.saveCurrentStudent — نمط Write-Ahead Log', () {
    test(
        'الحفظ الناجح (أونلاين + مزامنة ناجحة): يُكتَب أولاً في Hive '
        'ثم يُحذَف بعد نجاح المزامنة فقط', () async {
      final provider = GradingProvider();
      provider.debugSetOnline(true);
      provider.debugSetClassroom(_buildClassroom(classId: 5));

      var syncCalled = false;
      provider.debugSyncOverride = ({
        required int termId,
        required int weekNumber,
        required String subject,
        required List<Map<String, dynamic>> grades,
        int? classId,
      }) async {
        syncCalled = true;
        // في هذه اللحظة بالذات (قبل انتهاء "المزامنة")، البيانات
        // يجب أن تكون بالفعل مكتوبة على القرص (Write-Ahead) —
        // هذا هو جوهر الإصلاح: التحقق يحدث *أثناء* محاكاة انتظار
        // الشبكة، وليس بعده.
        final pendingDuringSync = StorageService.getPendingSyncs();
        expect(
          pendingDuringSync.any((p) => p.studentId == 101),
          isTrue,
          reason: 'يجب أن تكون الدرجات محفوظة في Hive قبل انتهاء '
              'استدعاء الشبكة — هذا هو جوهر إصلاح Write-Ahead Log. '
              'لو أُغلِق التطبيق في هذه اللحظة تحديداً، يجب ألا '
              'تُفقَد البيانات.',
        );
        return {'status': 'ok'};
      };

      provider.currentStudent!.grades['oral'] = 12;
      provider.currentStudent!.grades['written'] = 20;

      final result = await provider.saveCurrentStudent();

      expect(syncCalled, isTrue);
      expect(result, isTrue, reason: 'نجاح المزامنة يجب أن يُرجع true');

      // بعد نجاح المزامنة: يجب أن يُحذَف العنصر من قائمة الانتظار
      final pendingAfter = StorageService.getPendingSyncs();
      expect(
        pendingAfter.any((p) => p.studentId == 101),
        isFalse,
        reason: 'بعد نجاح المزامنة يجب حذف العنصر من قائمة الانتظار',
      );
      expect(provider.pendingCount, 0);
    });

    test(
        '🔴 محاكاة "إغلاق التطبيق أثناء الحفظ": حتى لو لم يُكتمل '
        'استدعاء الشبكة أبداً (Future معلّق للأبد)، تبقى البيانات '
        'مكتوبة بأمان على القرص فوراً', () async {
      final provider = GradingProvider();
      provider.debugSetOnline(true);
      provider.debugSetClassroom(_buildClassroom(classId: 7));

      // محاكاة انقطاع شبكة "يُعلّق" الطلب للأبد (Completer لا يُكمَل
      // أبداً) — يحاكي بالضبط سيناريو "قتل" التطبيق قبل استلام أي رد.
      provider.debugSyncOverride = ({
        required int termId,
        required int weekNumber,
        required String subject,
        required List<Map<String, dynamic>> grades,
        int? classId,
      }) {
        return Completer<Map<String, dynamic>>().future; // لا يكتمل أبداً
      };

      provider.currentStudent!.grades['oral'] = 9;
      provider.currentStudent!.grades['written'] = 18;

      // لا ننتظر (await) اكتمال saveCurrentStudent() بالكامل — تماماً
      // كما لو أن التطبيق قُتل في منتصف تنفيذها. نمنحها فرصة واحدة
      // فقط للوصول إلى نقطة الكتابة الأولى (microtask/IO turn) عبر
      // Future.delayed بمدة صفر لضمان انتهاء خطوة "الكتابة على القرص"
      // المتزامنة نسبياً قبل أن يتعلّق عند await الشبكة.
      // ignore: unawaited_futures
      provider.saveCurrentStudent();
      await Future.delayed(const Duration(milliseconds: 50));

      // التحقق الحاسم: البيانات موجودة في Hive رغم أن الحفظ لم
      // يكتمل منطقياً بعد (ولن يكتمل أبداً في هذا الاختبار).
      final pending = StorageService.getPendingSyncs();
      expect(
        pending.any((p) => p.studentId == 101 && p.classId == 7),
        isTrue,
        reason: 'حتى مع "تعليق" الشبكة للأبد (محاكاة قتل التطبيق)، '
            'يجب أن تكون الدرجات قد كُتبت بالفعل على القرص قبل '
            'استدعاء الشبكة — هذا يمنع فقدان البيانات نهائياً.',
      );
      expect(pending.first.grades['oral'], 9);
      expect(pending.first.grades['written'], 18);
    });

    test(
        'الفشل في المزامنة (خطأ شبكة): تبقى البيانات في قائمة الانتظار '
        'لإعادة المحاولة لاحقاً، ولا تُفقَد', () async {
      final provider = GradingProvider();
      provider.debugSetOnline(true);
      provider.debugSetClassroom(_buildClassroom(classId: 8));

      provider.debugSyncOverride = ({
        required int termId,
        required int weekNumber,
        required String subject,
        required List<Map<String, dynamic>> grades,
        int? classId,
      }) async {
        throw Exception('محاكاة انقطاع اتصال أثناء المزامنة');
      };

      provider.currentStudent!.grades['oral'] = 5;

      final result = await provider.saveCurrentStudent();

      expect(result, isFalse,
          reason: 'فشل المزامنة يجب أن يُرجع false (لكن البيانات آمنة)');

      final pending = StorageService.getPendingSyncs();
      expect(pending.any((p) => p.studentId == 101 && p.classId == 8), isTrue,
          reason: 'يجب أن تبقى البيانات في قائمة الانتظار بعد فشل '
              'المزامنة — لا يجوز فقدانها أو حذفها.');
      expect(provider.pendingCount, 1);
    });

    test(
        'الوضع الأوفلاين الصريح: تُكتَب البيانات فوراً في قائمة '
        'الانتظار دون أي محاولة اتصال بالشبكة إطلاقاً', () async {
      final provider = GradingProvider();
      provider.debugSetOnline(false); // أوفلاين من البداية
      provider.debugSetClassroom(_buildClassroom(classId: 9));

      var syncCalled = false;
      provider.debugSyncOverride = ({
        required int termId,
        required int weekNumber,
        required String subject,
        required List<Map<String, dynamic>> grades,
        int? classId,
      }) async {
        syncCalled = true;
        return {'status': 'should_not_be_called'};
      };

      provider.currentStudent!.grades['oral'] = 7;

      final result = await provider.saveCurrentStudent();

      expect(syncCalled, isFalse,
          reason: 'في الوضع الأوفلاين، لا يجب استدعاء الشبكة إطلاقاً');
      expect(result, isFalse);

      final pending = StorageService.getPendingSyncs();
      expect(pending.any((p) => p.studentId == 101 && p.classId == 9), isTrue,
          reason: 'يجب حفظ البيانات في قائمة الانتظار أوفلاين للمزامنة '
              'التلقائية لاحقاً عند عودة الاتصال.');
    });

    test(
        'فصل العرض التجريبي (classId=0): لا يُكتَب في قائمة الانتظار '
        'إطلاقاً حتى لا تتراكم بيانات وهمية', () async {
      final provider = GradingProvider();
      provider.debugSetOnline(true);
      provider.debugSetClassroom(_buildClassroom(classId: 0));

      provider.currentStudent!.grades['oral'] = 10;

      final result = await provider.saveCurrentStudent();

      expect(result, isFalse);
      final pending = StorageService.getPendingSyncs();
      expect(pending, isEmpty,
          reason: 'فصل العرض التجريبي (classId=0) يجب ألا يُضيف أي '
              'شيء لقائمة الانتظار الحقيقية إطلاقاً.');
    });

    test(
        'حفظ طالب بلا درجات مُدخَلة: لا يُكتَب شيء ولا يُستدعى أي '
        'اتصال شبكة (لا فائدة من حفظ بيانات فارغة)', () async {
      final provider = GradingProvider();
      provider.debugSetOnline(true);
      provider.debugSetClassroom(_buildClassroom(classId: 11));

      var syncCalled = false;
      provider.debugSyncOverride = ({
        required int termId,
        required int weekNumber,
        required String subject,
        required List<Map<String, dynamic>> grades,
        int? classId,
      }) async {
        syncCalled = true;
        return {};
      };

      // لم نُدخل أي درجة للطالب الحالي (grades فارغة)
      final result = await provider.saveCurrentStudent();

      expect(result, isFalse);
      expect(syncCalled, isFalse);
      expect(StorageService.getPendingSyncs(), isEmpty);
    });
  });

  group('StorageService.removePendingSync — الحذف الانتقائي الآمن', () {
    test(
        'يحذف فقط العنصر المطابق (studentId+subject) ويترك بقية '
        'العناصر المعلّقة الأخرى سليمة تماماً (لا حذف جماعي خاطئ)', () async {
      // نضيف ثلاثة عناصر معلّقة لطلاب/مواد مختلفة يدوياً عبر
      // addPendingSync (الواجهة العامة الوحيدة المتاحة).
      final provider = GradingProvider();
      provider.debugSetOnline(false); // نبقيها أوفلاين لتُكتَب فقط بلا مزامنة

      // طالب 1 - فصل 20
      provider.debugSetClassroom(
        _buildClassroom(
          classId: 20,
          students: [Student(id: 1, studentNumber: '001', name: 'أ')],
        ),
      );
      provider.currentStudent!.grades['oral'] = 5;
      await provider.saveCurrentStudent();

      // طالب 2 - فصل 20 (نفس الفصل، طالب مختلف)
      provider.debugSetClassroom(
        _buildClassroom(
          classId: 20,
          students: [Student(id: 2, studentNumber: '002', name: 'ب')],
        ),
      );
      provider.currentStudent!.grades['oral'] = 6;
      await provider.saveCurrentStudent();

      // طالب 3 - فصل مختلف تماماً 30
      provider.debugSetClassroom(
        _buildClassroom(
          classId: 30,
          students: [Student(id: 3, studentNumber: '003', name: 'ج')],
        ),
      );
      provider.currentStudent!.grades['oral'] = 7;
      await provider.saveCurrentStudent();

      expect(StorageService.getPendingSyncs().length, 3);

      // نحذف عنصر الطالب رقم 2 فقط (فصل 20، مادة رياضيات)
      await StorageService.removePendingSync(studentId: 2, subject: 'رياضيات');

      final remaining = StorageService.getPendingSyncs();
      expect(remaining.length, 2,
          reason: 'يجب أن يبقى عنصران فقط بعد حذف عنصر واحد تحديداً');
      expect(remaining.any((p) => p.studentId == 1), isTrue);
      expect(remaining.any((p) => p.studentId == 3), isTrue);
      expect(remaining.any((p) => p.studentId == 2), isFalse);
    });

    test('حذف عنصر غير موجود لا يُسبب أي خطأ ولا يُغيّر القائمة', () async {
      final provider = GradingProvider();
      provider.debugSetOnline(false);
      provider.debugSetClassroom(_buildClassroom(classId: 40));
      provider.currentStudent!.grades['oral'] = 3;
      await provider.saveCurrentStudent();

      expect(StorageService.getPendingSyncs().length, 1);

      // محاولة حذف عنصر غير موجود إطلاقاً
      await StorageService.removePendingSync(
        studentId: 9999,
        subject: 'مادة غير موجودة',
      );

      expect(StorageService.getPendingSyncs().length, 1,
          reason: 'يجب ألا تتأثر القائمة عند محاولة حذف عنصر غير '
              'موجود بها');
    });

    test('حذف آخر عنصر متبقٍ يُفرغ القائمة تماماً (pendingCount = 0)',
        () async {
      final provider = GradingProvider();
      provider.debugSetOnline(false);
      provider.debugSetClassroom(
        _buildClassroom(
          classId: 50,
          students: [Student(id: 500, studentNumber: '500', name: 'وحيد')],
        ),
      );
      provider.currentStudent!.grades['oral'] = 1;
      await provider.saveCurrentStudent();

      expect(StorageService.pendingCount, 1);

      await StorageService.removePendingSync(
          studentId: 500, subject: 'رياضيات');

      expect(StorageService.getPendingSyncs(), isEmpty);
      expect(StorageService.pendingCount, 0);
    });
  });
}
