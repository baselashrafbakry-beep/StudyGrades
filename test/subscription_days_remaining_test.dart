import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/models/subscription_model.dart';

/// اختبارات وظيفية حية لعطل daysRemaining Semantic Collision
/// (تم اكتشافه وإصلاحه أثناء المراجعة الأمنية الشاملة):
///
/// كان UserSubscription.fromJson() يستخدم clamp(-1, 9999) لحساب
/// daysRemaining من expiryDate، رغم أن القيمة -1 محجوزة حصرياً للدلالة
/// على "اشتراك مستمر بلا تاريخ انتهاء إطلاقاً" (UserSubscription.free()).
/// أي اشتراك مدفوع منتهي فعلياً (تاريخ الانتهاء في الماضي) كان سيُعاد
/// بناؤه بـ daysRemaining == -1 أيضاً — نفس قيمة "الاستمرارية بلا نهاية"،
/// مما يُشكِّل عطلاً كامناً خطيراً لأي كود مستقبلي يعتمد مباشرة على هذه
/// القيمة بدل isExpired/expiryDate.
void main() {
  group(
      'UserSubscription.fromJson — إصلاح تعارض داء daysRemaining (Semantic Collision)',
      () {
    test(
        'اشتراك مدفوع منتهي منذ 5 أيام يجب أن يُعيد daysRemaining = 0 (وليس -1)',
        () {
      final expiredDate =
          DateTime.now().subtract(const Duration(days: 5)).toIso8601String();
      final sub = UserSubscription.fromJson({
        'plan': 'pro',
        'start_date':
            DateTime.now().subtract(const Duration(days: 35)).toIso8601String(),
        'expiry_date': expiredDate,
        'is_active': true,
        'is_trial': false,
      });

      // الأهم: daysRemaining يجب ألا يكون -1 (قيمة "بلا نهاية" المحجوزة)
      expect(sub.daysRemaining, isNot(-1),
          reason:
              'اشتراك مدفوع منتهٍ فعلياً يجب ألا يحمل نفس قيمة "اشتراك مستمر بلا نهاية"');
      expect(sub.daysRemaining, equals(0));

      // ويجب أن يُصنَّف صحيحاً كمنتهي عبر isExpired بغضّ النظر عن daysRemaining
      expect(sub.isExpired, isTrue);
    });

    test('اشتراك مدفوع ينتهي اليوم بالضبط يُعيد daysRemaining = 0', () {
      // تاريخ انتهاء بعد ثوانٍ قليلة فقط من الآن (أقل من يوم كامل)
      final almostNow =
          DateTime.now().add(const Duration(hours: 2)).toIso8601String();
      final sub = UserSubscription.fromJson({
        'plan': 'basic',
        'expiry_date': almostNow,
        'is_active': true,
        'is_trial': false,
      });
      expect(sub.daysRemaining, equals(0));
      expect(sub.daysRemaining, isNot(-1));
    });

    test(
        'اشتراك مدفوع سارٍ فعلياً (30 يوم متبقٍ) يُعيد daysRemaining صحيحاً موجباً',
        () {
      final futureDate =
          DateTime.now().add(const Duration(days: 30)).toIso8601String();
      final sub = UserSubscription.fromJson({
        'plan': 'pro',
        'expiry_date': futureDate,
        'is_active': true,
        'is_trial': false,
      });
      // قد يكون 29 أو 30 حسب دقة الثواني وقت التنفيذ
      expect(sub.daysRemaining, greaterThanOrEqualTo(29));
      expect(sub.daysRemaining, lessThanOrEqualTo(30));
      expect(sub.isExpired, isFalse);
    });

    test(
        'عدم وجود expiry_date إطلاقاً (null) هو الحالة الوحيدة الصحيحة لـ daysRemaining = -1',
        () {
      final sub = UserSubscription.fromJson({
        'plan': 'school',
        'expiry_date': null,
        'is_active': true,
        'is_trial': false,
      });
      expect(sub.daysRemaining, equals(-1));
      expect(sub.isExpired, isFalse,
          reason: 'بدون تاريخ انتهاء، الاشتراك لا يمكن أن يكون منتهياً');
    });

    test(
        'UserSubscription.free() يحمل daysRemaining = -1 كقيمة استمرارية صحيحة',
        () {
      final freeSub = UserSubscription.free();
      expect(freeSub.daysRemaining, equals(-1));
      expect(freeSub.isExpired, isFalse);
      expect(freeSub.plan, equals(SubscriptionPlan.free));
    });

    test(
        'اشتراك منتهٍ منذ فترة طويلة (سنة كاملة) لا يُنتج قيمة سالبة كبيرة ولا -1',
        () {
      final longExpired =
          DateTime.now().subtract(const Duration(days: 365)).toIso8601String();
      final sub = UserSubscription.fromJson({
        'plan': 'pro',
        'expiry_date': longExpired,
        'is_active': true,
        'is_trial': false,
      });
      expect(sub.daysRemaining, equals(0));
      expect(sub.isExpired, isTrue);
    });

    test(
        'isExpiringSoon لا يُفعَّل خطأً لاشتراك منتهٍ فعلياً (daysRemaining=0)',
        () {
      final expiredDate =
          DateTime.now().subtract(const Duration(days: 2)).toIso8601String();
      final sub = UserSubscription.fromJson({
        'plan': 'basic',
        'expiry_date': expiredDate,
        'is_active': true,
        'is_trial': false,
      });
      // isExpiringSoon يشترط daysRemaining > 0، لذا يجب أن تكون false
      // لاشتراك منتهٍ بالفعل (daysRemaining == 0)، والحالة الصحيحة له
      // هي isExpired == true بدلاً من ذلك.
      expect(sub.isExpiringSoon, isFalse);
      expect(sub.isExpired, isTrue);
    });
  });
}
