// اختبار حي (Live Functional Test) لإصلاح ثغرة/عطل "معرّف الجهاز غير
// الثابت" (Device-ID Reinstall Bug) في SubscriptionService.getDeviceId().
//
// 🔴 المشكلة الأصلية المُكتشَفة:
// النسخة القديمة كانت تولّد معرّفاً عشوائياً بالكامل (Random.secure())
// وتخزّنه فقط في SharedPreferences، وهو تخزين يُمسح بالكامل عند حذف
// التطبيق/إعادة تثبيته على أندرويد. هذا يعني أن أي **عميل دافع حقيقي**
// اشترى كوداً مخصصاً لجهازه (SGV2-...) كان سيفقد صلاحية اشتراكه المدفوع
// بالكامل بعد إعادة تثبيت التطبيق أو تحديث هاتفه — رغم أنه نفس الجهاز
// فعلياً من منظور المستخدم.
//
// ✅ الإصلاح: استخدام Settings.Secure.ANDROID_ID (عبر حزمة android_id)
// كمصدر أساسي على أندرويد — وهو ثابت عبر إعادة التثبيت. للتوافق الخلفي،
// أي معرّف مخزَّن بالفعل في SharedPreferences (من نسخة سابقة أو من هذا
// التشغيل نفسه) يبقى له الأولوية المطلقة ولا يُستبدل أبداً.
//
// ⚠️ ملاحظة بيئة الاختبار: حزمة android_id تعتمد على MethodChannel أصلي
// (Native) غير مسجَّل في بيئة اختبار Dart VM العادية (flutter test)،
// لذلك ستفشل invokeMethod دائماً هنا بـ MissingPluginException، وهو ما
// يُعالجه الكود عبر try/catch بالتراجع التلقائي للتوليد العشوائي. هذا
// الاختبار يركّز إذن على الجزء القابل للتحقق فعلياً في هذه البيئة: منطق
// التوافق الخلفي (أولوية القيمة المخزَّنة) وثبات القيمة عبر نداءات متعددة.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_grades_voice/services/subscription_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_deviceid_test_');
    Hive.init(tempDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SubscriptionService.getDeviceId — ثبات المعرّف عبر الاستدعاءات', () {
    test('نداءان متتاليان بدون أي تخزين مسبق يُعيدان نفس القيمة بالضبط',
        () async {
      final id1 = await SubscriptionService.getDeviceId();
      final id2 = await SubscriptionService.getDeviceId();

      expect(id1, isNotEmpty);
      expect(id1, equals(id2),
          reason: 'يجب أن يبقى معرّف الجهاز ثابتاً عبر نداءات متعددة '
              'ضمن نفس الجلسة/التثبيت، دون توليد قيمة جديدة في كل مرة.');
    });

    test(
        'معرّف مخزَّن مسبقاً (من نسخة سابقة/تشغيل سابق) له الأولوية المطلقة '
        '(توافق خلفي — لا يُستبدَل أبداً)', () async {
      // محاكاة حالة "مستخدم قديم" لديه بالفعل معرّف مخزَّن في
      // SharedPreferences من نسخة سابقة من التطبيق (قبل إصلاح هذه الثغرة)
      const legacyStoredId = 'AABBCCDD11223344';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_license_id', legacyStoredId);

      final id = await SubscriptionService.getDeviceId();

      expect(id, equals(legacyStoredId),
          reason: 'المعرّف المخزَّن مسبقاً يجب أن يُستخدَم كما هو تماماً؛ '
              'أي اشتراك مدفوع مفعَّل بالفعل على هذا المعرّف يجب ألا '
              'ينكسر بسبب هذا التحديث.');
    });

    test(
        'المعرّف المُولَّد ليس فارغاً وبصيغة نصية صالحة للاستخدام كجزء '
        'من كود ترخيص (Base32-friendly / hex)', () async {
      final id = await SubscriptionService.getDeviceId();
      expect(id, isNotEmpty);
      expect(id.trim(), equals(id.toUpperCase().trim()));
    });
  });
}
