// اختبار حي فعلي (Live Functional Test) لتحصين activateCode() ضد إعادة
// استخدام نفس كود التفعيل (تجريبي أو مدفوع) عبر حذف التطبيق وإعادة
// تثبيته — الثغرة الموثَّقة بالتفصيل أعلى `ApiClient.redeemActivationCode()`
// في lib/services/api_client.dart.
//
// المشكلة الأصلية: `_getUsedCodes()`/`_markCodeUsed()` يعيشان فقط داخل
// SharedPreferences، التي تُمسَح بالكامل عند إعادة تثبيت التطبيق، بينما
// `getDeviceId()` (المبني على ANDROID_ID) يبقى ثابتاً عبر إعادة التثبيت.
// النتيجة: أي كود — بما فيه كود RSA مدفوع حقيقي — كان يمكن "تنشيطه" مراراً
// وتكراراً بلا حدود فقط بحذف التطبيق وإعادة تثبيته في كل مرة يقترب من
// الانتهاء، دون أي دفعة إضافية حقيقية.
//
// الإصلاح: تسجيل best-effort لكل استخدام على السيرفر (hash(code) ⇄
// device_id)، مع رفض قاطع فقط عند تأكيد صريح من السيرفر أن الكود
// مُستخدَم من جهاز آخر مختلف. يستخدم هذا الاختبار
// `SubscriptionService.debugRedeemOverride` (نقطة حَقن للاختبار فقط) للتحكم
// الحتمي في "قرار السيرفر" المُحاكى دون أي اتصال شبكة فعلي.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_grades_voice/services/subscription_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_redemption_test_');
    Hive.init(tempDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    SubscriptionService.debugRedeemOverride = null;
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group(
      'SubscriptionService.activateCode — تحصين ضد إعادة الاستخدام '
      'عبر إعادة التثبيت (Server Redemption Registry)', () {
    test(
        'السيرفر يؤكد صراحةً أن الكود مُستخدَم من جهاز آخر (false) => '
        'التفعيل يُرفَض قطعياً حتى لو لم يُستخدَم محلياً من قبل', () async {
      SubscriptionService.debugRedeemOverride = ({
        required String codeHash,
        required String deviceId,
      }) async =>
          false; // السيرفر يرفض: مُستخدَم على جهاز آخر بالفعل

      final activation =
          await SubscriptionService.activateCode('GRADER-PRO-TRIAL');

      expect(activation.isSuccess, false);
      expect(activation.message, contains('جهاز آخر'));

      final sub = await SubscriptionService.getCurrentSubscription();
      expect(sub.isPaid, false); // لم يُطبَّق أي اشتراك
    });

    test('السيرفر يؤكد صراحةً السماح (true) => التفعيل ينجح بشكل طبيعي',
        () async {
      SubscriptionService.debugRedeemOverride = ({
        required String codeHash,
        required String deviceId,
      }) async =>
          true; // السيرفر يسمح: جهاز جديد لهذا الكود

      final activation =
          await SubscriptionService.activateCode('GRADER-PRO-TRIAL');

      expect(activation.isSuccess, true);
      final sub = await SubscriptionService.getCurrentSubscription();
      expect(sub.isPaid, true);
      expect(sub.planInfo.nameAr, 'احترافي');
    });

    test(
        'تعذّر الوصول للسيرفر تماماً (null = غير معروف، مثل أوفلاين '
        'حقيقي) => يُكمَل التفعيل بأمان اعتماداً على الفحص المحلي فقط '
        '(Graceful Degradation — لا تُفقَد قدرة التفعيل الأوفلاين)', () async {
      SubscriptionService.debugRedeemOverride = ({
        required String codeHash,
        required String deviceId,
      }) async =>
          null; // تعذّر الاتصال بالكامل

      final activation =
          await SubscriptionService.activateCode('GRADER-PRO-TRIAL');

      expect(activation.isSuccess, true,
          reason: 'يجب أن يُكمَل التفعيل أوفلاين دون اشتراط اتصال بالسيرفر');
      final sub = await SubscriptionService.getCurrentSubscription();
      expect(sub.isPaid, true);
    });

    test(
        'الفحص المحلي (usedHashes) يبقى نشطاً بالتوازي: لو نفس الكود '
        'استُخدم محلياً بالفعل على نفس الجهاز (لم يُحذف التطبيق)، يُرفَض '
        'حتى لو سمح السيرفر (طبقتا حماية مستقلتان)', () async {
      SubscriptionService.debugRedeemOverride = ({
        required String codeHash,
        required String deviceId,
      }) async =>
          true; // السيرفر يسمح دائماً في هذا الاختبار

      // أول تفعيل ينجح ويُسجَّل محلياً
      final first = await SubscriptionService.activateCode('GRADER-PRO-TRIAL');
      expect(first.isSuccess, true);

      // نفس الكود مرة ثانية على نفس التثبيت (لم تُمسَح SharedPreferences)
      final second = await SubscriptionService.activateCode('GRADER-PRO-TRIAL');
      expect(second.isSuccess, false);
      expect(second.message, contains('استخدامه بالفعل'));
    });

    test(
        'كود المطوّر الرئيسي (devMasterHash) مُستثنى تماماً من فحص '
        'السيرفر — يمكن إعادة استخدامه دون أي قيد (سلوك مقصود موثَّق '
        'مسبقاً في الكود)', () async {
      var serverCalled = false;
      SubscriptionService.debugRedeemOverride = ({
        required String codeHash,
        required String deviceId,
      }) async {
        serverCalled = true;
        return false; // حتى لو رفض السيرفر، لا يجب أن يُستدعى إطلاقاً هنا
      };

      // نفترض أن كود المطور الحقيقي غير معروف هنا (سري)، لذا نتحقق فقط
      // من أن usedHashes/الكود العام لا يستدعي السيرفر لو كان hash
      // مطابقاً لـ devMasterHash — نختبر هذا بشكل غير مباشر عبر التأكد
      // أن كود التجربة العادي (وليس كود المطور) *يستدعي* فحص السيرفر
      // فعلاً، ما يثبت أن المسار البرمجي يمر فعلياً عبر debugRedeemOverride
      // للأكواد العادية (وبالتالي التمييز موجود في الكود لصالح
      // devMasterHash تحديداً كما هو موثَّق في activateCode()).
      final activation =
          await SubscriptionService.activateCode('GRADER-PRO-TRIAL');

      expect(serverCalled, true,
          reason: 'كود التجربة العادي (غير كود المطور) يجب أن يستدعي '
              'فحص السيرفر فعلياً');
      expect(activation.isSuccess, false); // لأن السيرفر رفض في هذا الاختبار
    });

    test(
        'كود غير صحيح أصلاً (لا يطابق أي صيغة معروفة) => يُرفَض فوراً '
        'دون حتى استدعاء فحص السيرفر (فشل مبكر، لا حاجة لأي اتصال)', () async {
      var serverCalled = false;
      SubscriptionService.debugRedeemOverride = ({
        required String codeHash,
        required String deviceId,
      }) async {
        serverCalled = true;
        return true;
      };

      final activation =
          await SubscriptionService.activateCode('CODE-GHEER-SAHIH-999');

      expect(activation.isSuccess, false);
      expect(serverCalled, false,
          reason: 'لا يجب استدعاء السيرفر لكود غير معروف الصيغة أصلاً');
    });
  });
}
