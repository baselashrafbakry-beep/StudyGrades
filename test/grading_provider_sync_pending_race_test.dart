// اختبار حي (Live Functional Test) لإصلاح ثغرة "حالة السباق الصامتة"
// (Silent Race Condition) في GradingProvider.syncPendingGrades()
// — ثغرة إضافية اكتُشفت أثناء تدقيق Pillar 1 (خارج الحالات الثلاث
// المُسمّاة صراحةً من المستخدم، لكنها من نفس فئة "فقدان بيانات
// المزامنة عند انقطاع/تزامن الشبكة").
//
// 🔴 المشكلة الأصلية المُكتشَفة:
// كانت `syncPendingGrades()` تأخذ لقطة واحدة من قائمة الانتظار في
// بداية تنفيذها (`pending = StorageService.getPendingSyncs()`)، ثم
// بعد إتمام حلقة مزامنة قد تستغرق عدة ثوانٍ (طلبات شبكة متعددة)، كانت
// تُنفّذ إما `clearPendingSyncs()` (مسح الصندوق بأكمله) أو
// `replacePendingSyncs(failed)` (استبدال الصندوق بأكمله بالعناصر
// الفاشلة فقط) — استناداً حصرياً إلى تلك اللقطة القديمة.
//
// إذا أُضيف عنصر جديد إلى صندوق الانتظار في Hive *أثناء* تنفيذ حلقة
// المزامنة (مثلاً: المستخدم يحفظ درجة طالب آخر عبر saveCurrentStudent()
// بينما مزامنة جماعية أخرى قيد التنفيذ فعلاً)، فإن هذا العنصر الجديد:
//   1) غير موجود في اللقطة الأصلية (pending) — فلن تتم مزامنته إطلاقاً
//      في هذه الدورة.
//   2) لكنه مكتوب بالفعل على القرص (Write-Ahead).
//   3) عند وصول الدالة لنهايتها وتنفيذ clearPendingSyncs()/
//      replacePendingSyncs() المستندين على اللقطة القديمة فقط — يُحذَف
//      هذا العنصر الجديد **بصمت تام** رغم عدم محاولة مزامنته أبداً.
//
// ✅ الإصلاح: إزالة كل عمليات "المسح/الاستبدال الشامل"، والاستعاضة
// عنها بحذف انتقائي (`removePendingSync`) لكل عنصر فور نجاح مزامنته
// تحديداً هو. أي عنصر يُضاف أثناء تنفيذ الدالة يبقى بأمان تام في
// الصندوق ولا يُلمَس أبداً ما لم تتم مزامنته صراحةً بنفسه لاحقاً.

import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:study_grades_voice/models/student_model.dart';
import 'package:study_grades_voice/providers/grading_provider.dart';
import 'package:study_grades_voice/services/storage_service.dart';

ClassroomData _buildClassroom({
  required int classId,
  required String subject,
  List<Student>? students,
}) {
  return ClassroomData(
    classId: classId,
    className: 'فصل الاختبار',
    subject: subject,
    fields: [GradeField(name: 'oral', label: 'شفهي', max: 15)],
    students: students ??
        [Student(id: 1, studentNumber: '001', name: 'طالب الاختبار')],
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_sync_race_test_');
    Hive.init(tempDir.path);
    await StorageService.init();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('GradingProvider.syncPendingGrades — إصلاح Race Condition', () {
    test(
        '🔴 عنصر جديد يُضاف أثناء تنفيذ المزامنة الجماعية يجب ألا '
        'يُحذَف بصمت — يجب أن يبقى في قائمة الانتظار لأن مزامنته لم '
        'تُحاوَل إطلاقاً', () async {
      final provider = GradingProvider();
      provider.debugSetOnline(true);

      // العنصر الأول: طالب 1، مادة "رياضيات"، فصل 100
      provider.debugSetClassroom(
        _buildClassroom(
          classId: 100,
          subject: 'رياضيات',
          students: [Student(id: 1, studentNumber: '001', name: 'أ')],
        ),
      );
      provider.currentStudent!.grades['oral'] = 10;
      // نحفظه أوفلاين أولاً لضمان وجوده في قائمة الانتظار فقط (بدون
      // مزامنة فورية)، ثم نُفعّل أونلاين لاستدعاء syncPendingGrades().
      provider.debugSetOnline(false);
      await provider.saveCurrentStudent();
      provider.debugSetOnline(true);

      expect(StorageService.getPendingSyncs().length, 1);

      // نُعِدّ محاكاة شبكة "بطيئة" تسمح لنا بحقن عنصر جديد في منتصف
      // تنفيذ حلقة المزامنة (قبل أن تكتمل، وقبل أن تُنفّذ الدالة أي
      // عملية حذف نهائية).
      final networkGate = Completer<void>();
      provider.debugSyncOverride = ({
        required int termId,
        required int weekNumber,
        required String subject,
        required List<Map<String, dynamic>> grades,
        int? classId,
      }) async {
        // ننتظر حتى يُشير الاختبار بأن العنصر الجديد قد أُضيف بالفعل
        await networkGate.future;
        return {'status': 'ok'};
      };

      // نبدأ المزامنة الجماعية دون انتظارها فوراً (محاكاة عملية طويلة
      // قيد التنفيذ في الخلفية).
      final syncFuture = provider.syncPendingGrades();

      // بينما المزامنة الجماعية "قيد التنفيذ" (منتظرة عند networkGate)،
      // نضيف عنصراً جديداً تماماً لطالب آخر في فصل مختلف — يحاكي
      // المستخدم وهو يحفظ درجة طالب جديد أثناء تشغيل المزامنة في
      // الخلفية.
      provider.debugSetClassroom(
        _buildClassroom(
          classId: 200,
          subject: 'علوم',
          students: [Student(id: 2, studentNumber: '002', name: 'ب')],
        ),
      );
      // العنصر الجديد يجب ألا يُزامَن في هذه الدورة إطلاقاً — نُبقيه
      // أوفلاين فعلياً عبر debugSyncOverride منفصل غير مُستخدَم هنا؛
      // الأبسط: نكتبه مباشرة عبر saveCurrentStudent() في وضع أونلاين
      // لكن قبل فك قفل الشبكة — بما أن debugSyncOverride مشترك بين
      // النداءين، سيُعلَّق هذا الحفظ أيضاً على نفس الـ gate. لتفادي
      // التعقيد، نُبقيه أوفلاين فيُكتَب فوراً دون انتظار الشبكة إطلاقاً.
      provider.debugSetOnline(false);
      provider.currentStudent!.grades['oral'] = 5;
      await provider.saveCurrentStudent();
      provider.debugSetOnline(true);

      // الآن قائمة الانتظار تحوي عنصرين: الأصلي (قيد المزامنة فعلياً)
      // والجديد (لم تبدأ مزامنته بعد).
      expect(StorageService.getPendingSyncs().length, 2);

      // نُحرّر بوابة الشبكة لإكمال المزامنة الجماعية الأصلية.
      networkGate.complete();
      final synced = await syncFuture;

      expect(synced, 1, reason: 'يجب مزامنة العنصر الأصلي فقط (طالب 1)');

      final remaining = StorageService.getPendingSyncs();
      expect(
        remaining.length,
        1,
        reason: 'يجب أن يبقى العنصر الجديد (طالب 2) في قائمة الانتظار '
            'لأن مزامنته لم تُحاوَل إطلاقاً في هذه الدورة — قبل '
            'الإصلاح كان clearPendingSyncs()/replacePendingSyncs() '
            'يحذفه بصمت رغم ذلك.',
      );
      expect(remaining.first.studentId, 2,
          reason: 'العنصر المتبقي يجب أن يكون تحديداً طالب 2 الجديد، '
              'وليس طالب 1 الذي تمت مزامنته فعلاً.');
    });

    test(
        'المزامنة الناجحة الكاملة (بدون تزامن): تُحذَف كل العناصر '
        'المُزامَنة بنجاح ولا يبقى شيء', () async {
      final provider = GradingProvider();
      provider.debugSetOnline(false);
      provider.debugSetClassroom(
        _buildClassroom(
          classId: 300,
          subject: 'رياضيات',
          students: [Student(id: 10, studentNumber: '010', name: 'ج')],
        ),
      );
      provider.currentStudent!.grades['oral'] = 8;
      await provider.saveCurrentStudent();

      provider.debugSetClassroom(
        _buildClassroom(
          classId: 300,
          subject: 'رياضيات',
          students: [Student(id: 11, studentNumber: '011', name: 'د')],
        ),
      );
      provider.currentStudent!.grades['oral'] = 9;
      await provider.saveCurrentStudent();

      expect(StorageService.getPendingSyncs().length, 2);

      provider.debugSetOnline(true);
      provider.debugSyncOverride = ({
        required int termId,
        required int weekNumber,
        required String subject,
        required List<Map<String, dynamic>> grades,
        int? classId,
      }) async {
        return {'status': 'ok'};
      };

      final synced = await provider.syncPendingGrades();

      expect(synced, 2);
      expect(StorageService.getPendingSyncs(), isEmpty);
      expect(provider.pendingCount, 0);
    });

    test(
        'فشل مزامنة دفعة كاملة (خطأ شبكة): تبقى عناصرها في قائمة '
        'الانتظار كما هي دون أي حذف', () async {
      final provider = GradingProvider();
      provider.debugSetOnline(false);
      provider.debugSetClassroom(
        _buildClassroom(
          classId: 400,
          subject: 'رياضيات',
          students: [Student(id: 20, studentNumber: '020', name: 'هـ')],
        ),
      );
      provider.currentStudent!.grades['oral'] = 4;
      await provider.saveCurrentStudent();

      provider.debugSetOnline(true);
      provider.debugSyncOverride = ({
        required int termId,
        required int weekNumber,
        required String subject,
        required List<Map<String, dynamic>> grades,
        int? classId,
      }) async {
        throw Exception('محاكاة فشل شبكة أثناء المزامنة الجماعية');
      };

      final synced = await provider.syncPendingGrades();

      expect(synced, 0);
      final remaining = StorageService.getPendingSyncs();
      expect(remaining.length, 1,
          reason: 'يجب أن يبقى العنصر الفاشل في قائمة الانتظار '
              'لإعادة المحاولة لاحقاً، وليس أن يُحذَف أو يُفقَد.');
      expect(remaining.first.studentId, 20);
    });

    test(
        'مزامنة جزئية عبر مواد/فصول متعددة: تنجح دفعة وتفشل أخرى، '
        'فتُحذَف الناجحة فقط وتبقى الفاشلة', () async {
      final provider = GradingProvider();
      provider.debugSetOnline(false);

      // دفعة أولى: فصل 500 / رياضيات (ستنجح)
      provider.debugSetClassroom(
        _buildClassroom(
          classId: 500,
          subject: 'رياضيات',
          students: [Student(id: 30, studentNumber: '030', name: 'و')],
        ),
      );
      provider.currentStudent!.grades['oral'] = 6;
      await provider.saveCurrentStudent();

      // دفعة ثانية: فصل 600 / علوم (ستفشل)
      provider.debugSetClassroom(
        _buildClassroom(
          classId: 600,
          subject: 'علوم',
          students: [Student(id: 40, studentNumber: '040', name: 'ز')],
        ),
      );
      provider.currentStudent!.grades['oral'] = 7;
      await provider.saveCurrentStudent();

      expect(StorageService.getPendingSyncs().length, 2);

      provider.debugSetOnline(true);
      provider.debugSyncOverride = ({
        required int termId,
        required int weekNumber,
        required String subject,
        required List<Map<String, dynamic>> grades,
        int? classId,
      }) async {
        if (subject == 'علوم') {
          throw Exception('محاكاة فشل شبكة لمادة العلوم فقط');
        }
        return {'status': 'ok'};
      };

      final synced = await provider.syncPendingGrades();

      expect(synced, 1, reason: 'دفعة الرياضيات فقط يجب أن تنجح');
      final remaining = StorageService.getPendingSyncs();
      expect(remaining.length, 1);
      expect(remaining.first.studentId, 40,
          reason: 'يجب أن يبقى طالب العلوم الفاشل فقط في قائمة الانتظار');
      expect(remaining.first.subject, 'علوم');
    });
  });
}
