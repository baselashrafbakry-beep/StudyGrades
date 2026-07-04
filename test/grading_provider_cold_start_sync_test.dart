// اختبار حي (Live Functional Test) لإصلاح ثغرة "فقدان مزامنة بدء
// التشغيل الباردة" (Cold-Start Sync Gap) في GradingProvider.
//
// 🔴 المشكلة الأصلية المُكتشَفة (Pillar 3 — مراجعة وضع عدم الاتصال):
// كانت المزامنة التلقائية عند عودة الاتصال تعتمد حصرياً على الاستماع
// لتيار `connectivityService.onStatusChange`، والذي لا يُطلِق أي حدث
// إلا عند حدوث *تحوّل فعلي* من أوفلاين إلى أونلاين أثناء عمر التطبيق
// الحالي. لكن هذا لا يغطي السيناريو الشائع التالي:
//
//   1) المستخدم يحفظ درجات أثناء انقطاع الاتصال → تُكتب في قائمة
//      الانتظار (Hive pending_grades_box) عبر نمط Write-Ahead Log.
//   2) يُغلق المستخدم التطبيق تماماً (لم تتم أي مزامنة بعد).
//   3) يعيد المستخدم فتح التطبيق **وهو متصل بالإنترنت بالفعل منذ
//      اللحظة الأولى** (مثلاً: اتصل بشبكة واي فاي بينما التطبيق مغلق).
//
// في هذا السيناريو، لا يحدث أي "تحوّل" في حالة الاتصال أثناء الجلسة
// الجديدة — فتبقى الدرجات المعلّقة عالقة بصمت في Hive إلى أن يكتشف
// المستخدم بنفسه وجود بيانات معلّقة (عبر شارة العدّاد) ويضغط زر
// "مزامنة" يدوياً من الإعدادات/الرئيسية/سجل النشاط.
//
// ✅ الإصلاح: عند إنشاء GradingProvider (أي عند بدء الجلسة)، إذا كان
// الجهاز متصلاً بالفعل ويوجد عناصر معلّقة من جلسة سابقة → يُطلَق محاولة
// مزامنة فورية تلقائياً (fire-and-forget عبر Future.microtask) دون
// انتظار أي حدث تحوّل في حالة الاتصال.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:study_grades_voice/models/pending_sync.dart';
import 'package:study_grades_voice/providers/grading_provider.dart';
import 'package:study_grades_voice/services/storage_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_cold_start_test_');
    Hive.init(tempDir.path);
    await StorageService.init();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('GradingProvider — إصلاح ثغرة مزامنة بدء التشغيل الباردة', () {
    test(
        '🔴 عناصر معلّقة من جلسة سابقة + جهاز متصل منذ البداية → يجب '
        'مزامنتها تلقائياً دون انتظار أي "تحوّل" في حالة الاتصال', () async {
      // محاكاة "الجلسة السابقة": درجة طالب محفوظة في قائمة الانتظار
      // مباشرة عبر StorageService (كما لو حُفظت أوفلاين قبل إغلاق
      // التطبيق ولم تُزامَن أبداً).
      await StorageService.addPendingSync(
        PendingSync(
          studentId: 501,
          studentName: 'طالب الجلسة السابقة',
          grades: {'oral': 12},
          timestamp: DateTime.now().toIso8601String(),
          classId: 9,
          subject: 'العلوم',
        ),
      );
      expect(StorageService.pendingCount, 1);

      // "إعادة فتح التطبيق": إنشاء GradingProvider جديد. بما أن
      // connectivityService الحقيقية (المُهيَّأة افتراضياً بـ
      // _isOnline = true في هذه البيئة) لن تُطلق أي حدث "تحوّل" هنا
      // (هي بالفعل أونلاين ولن تتغيّر)، فإن مسار onStatusChange وحده
      // لن يكتشف العناصر المعلّقة إطلاقاً — وهذا بالضبط ما تختبره
      // هذه الحالة: الاعتماد على مسار Cold-Start الجديد بدلاً منه.
      final provider = GradingProvider();

      var syncCalled = false;
      final completer = Completer<void>();
      provider.debugSyncOverride = ({
        required int termId,
        required int weekNumber,
        required String subject,
        required List<Map<String, dynamic>> grades,
        int? classId,
      }) async {
        syncCalled = true;
        expect(subject, 'العلوم');
        expect(classId, 9);
        expect(grades.first['student_id'], 501);
        if (!completer.isCompleted) completer.complete();
        return {'status': 'ok'};
      };

      // ننتظر اكتمال محاولة المزامنة المؤجَّلة (Future.microtask) —
      // مهلة قصيرة كافية جداً لأن المزامنة هنا مُحاكاة (بدون شبكة حقيقية).
      await completer.future.timeout(const Duration(seconds: 2));

      expect(syncCalled, isTrue,
          reason: 'يجب أن يُستدعى syncPendingGrades() تلقائياً عند بدء '
              'التشغيل طالما الجهاز متصل ويوجد عناصر معلّقة — دون '
              'انتظار أي حدث تحوّل في حالة الاتصال');

      // انتظار قصير إضافي لضمان اكتمال منطق ما-بعد-المزامنة (حذف
      // العنصر من قائمة الانتظار) قبل التحقق النهائي.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        StorageService.pendingCount,
        0,
        reason: 'بعد نجاح المزامنة التلقائية عند بدء التشغيل، يجب أن '
            'تُحذَف العناصر المعلّقة من قائمة الانتظار',
      );
    });

    test(
        'لا يوجد عناصر معلّقة → لا تُستدعى المزامنة إطلاقاً عند بدء '
        'التشغيل (لا حاجة، ولا ضرر أيضاً لو استُدعيت — لكن نتحقق أنها '
        'لا تُستدعى بلا داعٍ)', () async {
      expect(StorageService.pendingCount, 0);

      final provider = GradingProvider();
      var syncCalled = false;
      provider.debugSyncOverride = ({
        required int termId,
        required int weekNumber,
        required String subject,
        required List<Map<String, dynamic>> grades,
        int? classId,
      }) async {
        syncCalled = true;
        return {'status': 'ok'};
      };

      // مهلة قصيرة لإتاحة الفرصة لأي مزامنة مؤجَّلة (لو وُجدت خطأً) كي
      // تظهر — لا يوجد شيء لانتظاره فعلياً هنا لأن لا عناصر معلّقة.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(syncCalled, isFalse,
          reason: 'بدون عناصر معلّقة، لا داعي لاستدعاء المزامنة عند '
              'بدء التشغيل إطلاقاً');
    });
  });
}
