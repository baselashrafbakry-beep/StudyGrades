// اختبار حي فعلي (Live Functional Test) لتحصين نظام الاشتراك ضد "التلاعب
// بساعة الجهاز" (Clock Manipulation) — الثغرة التجارية المكتشَفة أثناء
// تدقيق Pillar 2: بما أن كل منطق انتهاء الاشتراك كان يعتمد حصرياً على
// `DateTime.now()` الخام، كان بإمكان أي مستخدم عادي (بدون صلاحيات جذر)
// إرجاع ساعة/تاريخ جهازه للخلف يدوياً (من إعدادات أندرويد العادية) في كل
// مرة يقترب فيها اشتراكه — تجريبياً كان أو **مدفوعاً حقيقياً عبر كود
// RSA** — من الانتهاء، ليبقى `expiryDate.isAfter(now)` صحيحاً إلى الأبد.
//
// الإصلاح المُختبَر هنا: "المزلاج الزمني الأحادي الاتجاه" (Monotonic Time
// Ratchet) عبر `SubscriptionService._licenseNow()` (يُختبَر بشكل غير مباشر
// عبر السلوك العلني في `getCurrentSubscription()` و`activateCode()`، بما
// أن `_licenseNow` نفسها خاصة). نستخدم `SubscriptionService.
// debugClockOverride` (نقطة حَقن للاختبار فقط) للتحكم الحتمي الكامل في
// "الوقت الحالي" المُستخدَم من قِبل الخدمة، دون انتظار زمن حقيقي أو
// التلاعب الفعلي بساعة نظام التشغيل أثناء الاختبار.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_grades_voice/models/subscription_model.dart';
import 'package:study_grades_voice/services/subscription_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_clock_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings_box');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    SubscriptionService.debugClockOverride = null;
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SubscriptionService — تحصين ضد التلاعب بساعة الجهاز (Clock Ratchet)',
      () {
    test(
        'تقدّم الوقت الطبيعي: daysRemaining يتناقص بشكل صحيح مع مرور الوقت الحقيقي',
        () async {
      final day0 = DateTime(2026, 1, 1);
      SubscriptionService.debugClockOverride = () => day0;

      final result = await SubscriptionService.activateCode('GRADER-PRO-TRIAL');
      expect(result.isSuccess, true);
      expect(result.subscription!.plan, SubscriptionPlan.pro);

      // تقدّم الوقت الحقيقي (المزلاج يتحرك أيضاً بأمان) 5 أيام
      SubscriptionService.debugClockOverride = () => day0.add(
            const Duration(days: 5),
          );

      final sub = await SubscriptionService.getCurrentSubscription();
      expect(sub.isActive, true);
      // 14 يوم تجربة - 5 أيام مرت = 9 أيام متبقية
      expect(sub.daysRemaining, 9);
    });

    test(
        'إرجاع الساعة للخلف بعد أن تجاوز الوقت الحقيقي بالفعل تاريخ الانتهاء'
        ' => الاشتراك يبقى منتهياً (المزلاج يحفظ آخر وقت حقيقي أُبلِغ عنه)',
        () async {
      final day0 = DateTime(2026, 1, 1);
      SubscriptionService.debugClockOverride = () => day0;

      // تفعيل كود تجربة "أساسي" (30 يوماً)
      final result = await SubscriptionService.activateCode('STUDY2026-TRIAL');
      expect(result.isSuccess, true);

      // الوقت الحقيقي يتقدّم فعلياً إلى ما بعد الانتهاء (40 يوماً > 30)
      // — هذا يُسجِّل هذه اللحظة المتأخرة في المزلاج المحلي.
      SubscriptionService.debugClockOverride = () => day0.add(
            const Duration(days: 40),
          );
      final expiredCheck = await SubscriptionService.getCurrentSubscription();
      expect(expiredCheck.plan, SubscriptionPlan.free); // انتهى فعلاً بالفعل

      // 🔴 محاولة التلاعب: إرجاع "ساعة الجهاز" للخلف إلى داخل الفترة
      // الأصلية الصالحة (اليوم الخامس فقط من أصل 30) — لو كان النظام
      // يعتمد على DateTime.now() الخام لعاد الاشتراك "صالحاً" فوراً.
      SubscriptionService.debugClockOverride = () => day0.add(
            const Duration(days: 5),
          );
      final afterRollback = await SubscriptionService.getCurrentSubscription();

      // ✅ يبقى منتهياً/مجانياً رغم إرجاع الساعة، لأن المزلاج يتذكر أن
      // الوقت الحقيقي تجاوز بالفعل اليوم الأربعين.
      expect(afterRollback.plan, SubscriptionPlan.free);
    });

    test(
        'تمديد اشتراك جديد بعد أن انتهى الحالي فعلياً (حسب المزلاج) يبدأ من'
        ' "الآن" الآمن، وليس من تاريخ انتهاء الاشتراك القديم المنتهي فعلياً',
        () async {
      final day0 = DateTime(2026, 1, 1);
      SubscriptionService.debugClockOverride = () => day0;
      await SubscriptionService.activateCode('GRADER-PRO-TRIAL'); // 14 يوم

      // الوقت الحقيقي يتقدّم لما بعد الانتهاء (يُسجَّل في المزلاج)
      SubscriptionService.debugClockOverride = () => day0.add(
            const Duration(days: 20),
          );
      final expired = await SubscriptionService.getCurrentSubscription();
      expect(expired.plan, SubscriptionPlan.free);

      // المستخدم يرجع الساعة للخلف إلى داخل الفترة الأصلية، ثم يفعّل كوداً
      // جديداً (تجربة أساسي) — يجب أن يبدأ الاشتراك الجديد من "الآن الآمن"
      // (اليوم العشرين، وفق المزلاج) وليس يُمدَّد من تاريخ الانتهاء القديم
      // (اليوم الرابع عشر) الذي انقضى بالفعل حقيقياً.
      SubscriptionService.debugClockOverride = () => day0.add(
            const Duration(days: 3),
          );
      final result2 =
          await SubscriptionService.activateCode('STUDY2026-TRIAL'); // 30 يوم
      expect(result2.isSuccess, true);

      // تاريخ انتهاء الاشتراك الجديد يجب أن يكون day0+20+30 (بدءاً من آخر
      // وقت آمن معروف)، وليس day0+14+30 (تمديد خاطئ من انتهاء قديم).
      final expectedExpiry = day0.add(const Duration(days: 20 + 30));
      expect(
        result2.subscription!.expiryDate!.difference(expectedExpiry).inHours,
        lessThan(1),
      );
    });

    test(
        'تقديم الساعة للأمام بشكل طبيعي (بلا أي محاولة تلاعب) يُحدِّث المزلاج'
        ' بأمان دون أي مشاكل — سلوك طبيعي متوقَّع', () async {
      final day0 = DateTime(2026, 1, 1);
      SubscriptionService.debugClockOverride = () => day0;
      await SubscriptionService.activateCode('GRADER-PRO-TRIAL'); // 14 يوم

      SubscriptionService.debugClockOverride = () => day0.add(
            const Duration(days: 2),
          );
      final sub1 = await SubscriptionService.getCurrentSubscription();
      expect(sub1.daysRemaining, 12);

      SubscriptionService.debugClockOverride = () => day0.add(
            const Duration(days: 7),
          );
      final sub2 = await SubscriptionService.getCurrentSubscription();
      expect(sub2.daysRemaining, 7);
      expect(sub2.isActive, true);
    });

    test(
        'أول استخدام على الإطلاق بلا أي مزلاج مخزَّن سابقاً => يُستخدَم الوقت'
        ' "الحالي" المُعطى مباشرة دون أي تعديل (لا يوجد أساس سابق للمقارنة)',
        () async {
      final now = DateTime(2026, 6, 15);
      SubscriptionService.debugClockOverride = () => now;

      final result = await SubscriptionService.activateCode('GRADER-PRO-TRIAL');
      expect(result.isSuccess, true);
      final expectedExpiry = now.add(const Duration(days: 14));
      expect(
        result.subscription!.expiryDate!.difference(expectedExpiry).inHours,
        lessThan(1),
      );
    });
  });
}
