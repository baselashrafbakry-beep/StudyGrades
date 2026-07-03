// ⚠️ اختبار تراجع أمني دائم (Regression Test) — تاريخ الثغرة وتأكيد الإصلاح
//
// هذا الملف كان في الأصل اختبار إثبات ثغرة (Proof-of-Concept) يُثبت أن أي
// مستخدم عادي (دون أي صلاحية أو دفع) كان يستطيع توليد كود اشتراك "مدرسة"
// (أغلى خطة، بلا انتهاء) صالح فعلياً عبر SubscriptionService.activateCode()
// الحقيقي، لمجرد أنه يملك:
//   1) نسخة الـ APK/الويب المُصرَّفة (يُستخرج منها الـ salt الثابت بسهولة)
//   2) معرّف جهازه الخاص (متاح بنص صريح داخل SharedPreferences، أو حتى
//      بعرضه في واجهة "معرّف الجهاز" بالتطبيق نفسه)
//
// 🔧 تم إصلاح هذه الثغرة جذرياً عبر الانتقال من نظام توقيع متماثل (HMAC/
// SHA-256 قائم على salt ثابت مضمّن في الكود) إلى نظام توقيع لا متماثل
// (RSA-2048 + PSS padding) حيث المفتاح الخاص لا يُشحن أبداً مع التطبيق —
// فقط المفتاح العام (الذي لا يمكن استخدامه لتزوير توقيعات جديدة) موجود
// داخل lib/security/license_public_key.dart.
//
// الآن أصبح هذا الملف اختباراً دائماً يُعيد تشغيل نفس هجوم التزوير الأصلي
// (بنفس الـ salt المُستخرَج فعلياً من البناء القديم) للتأكد أنه **مرفوض**
// بشكل قاطع من قِبل الكود الإنتاجي الحالي — أي انحدار مستقبلي (رجوع عرضي
// لمنطق قديم أو ثغرة مشابهة) سيؤدي لفشل هذا الاختبار فوراً.

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_grades_voice/services/subscription_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_poc_test_');
    Hive.init(tempDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    '🟢 [إصلاح مؤكَّد] إعادة تشغيل هجوم التزوير الأصلي (النظام المتماثل '
    'القديم) يجب أن يُرفض الآن قطعياً من قِبل activateCode() بعد الترقية '
    'إلى RSA-2048/PSS',
    () async {
      // الخطوة 1: نفس معرّف الجهاز الحقيقي للتطبيق (سلوك طبيعي وشرعي).
      final deviceId = await SubscriptionService.getDeviceId();
      expect(deviceId, isNotEmpty);

      // الخطوة 2: نفس الـ salt الثابت الذي كان مستخرَجاً فعلياً من البناء
      // القديم عبر `strings` على main.dart.js / libapp.so قبل الإصلاح.
      const extractedSalt = 'SGV_2026_BASEL_SECURE';

      // الخطوة 3: نفس خوارزمية SHA-256 المتماثلة القديمة (_personalizedHash
      // سابقاً) — محاكاة كاملة للهجوم الأصلي بدون أي تعديل.
      String forgeHash(String devId, String planCode, int days) {
        final bytes = utf8.encode(
            '$extractedSalt:PERSONAL:${devId.toUpperCase()}:${planCode.toUpperCase()}:$days');
        return sha256.convert(bytes).toString().substring(0, 10).toUpperCase();
      }

      const plan = 'SCHOOL'; // أغلى خطة (2999 جنيه/سنة) وتفتح لوحة الأدمن
      const days = 9999; // "لا ينتهي" حسب منطق التطبيق نفسه
      final forgedHash = forgeHash(deviceId, plan, days);
      final forgedCode = 'SGV-$plan-$days-$forgedHash'; // الصيغة القديمة V1

      // الخطوة 4: محاولة تفعيل الكود المُزوَّر عبر واجهة الخدمة الحقيقية
      // 100% (نفس المسار الذي تستدعيه ActivateSubscriptionScreen فعلياً).
      final result = await SubscriptionService.activateCode(forgedCode);

      // ✅ بعد الإصلاح: يجب أن يُرفض هذا الكود المُزوَّر بشكل قاطع، لأن
      // الصيغة القديمة (SGV-...) لم تعد معترفاً بها إطلاقاً — النظام
      // الجديد يتطلب صيغة SGV2-... موقّعة رقمياً بمفتاح RSA خاص لا يملكه
      // إلا المطوّر، ولا يمكن اشتقاقه من أي شيء موجود داخل التطبيق نفسه.
      expect(result.isSuccess, false,
          reason: 'تأكيد الإصلاح: يجب رفض كود الصيغة القديمة المُزوَّر '
              'تماماً بعد الترقية إلى نظام التوقيع اللامتماثل RSA-2048/PSS.');

      // التأكد أيضاً أن المستخدم لم يحصل على أي اشتراك مدفوع كنتيجة جانبية.
      final sub = await SubscriptionService.getCurrentSubscription();
      expect(sub.isPaid, false,
          reason: 'يجب ألا يبقى أي أثر لاشتراك مفعّل بعد رفض الكود المزوَّر.');
    },
  );
}
