import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_grades_voice/services/subscription_service.dart';

/// اختبارات تكامل حية لنظام التراخيص الجديد (RSA-2048 / PSS) عبر المسار
/// الإنتاجي الفعلي SubscriptionService.activateCode() — بدون أي محاكاة.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_rsa_test_');
    Hive.init(tempDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('✅ كود مُوقَّع رقمياً وصحيح (لهذا الجهاز بالضبط) يُفعَّل بنجاح',
      () async {
    // الحصول على معرّف الجهاز الفعلي الذي سيولّده التطبيق لهذه البيئة،
    // ثم تشغيل أداة التوقيع الخارجية (Python) عليه فعلياً لتوليد كود حقيقي.
    final deviceId = await SubscriptionService.getDeviceId();

    final result = await Process.run('python3', [
      '/home/user/dev_tools/generate_license.py',
      '--device-id',
      deviceId,
      '--plan',
      'PRO',
      '--days',
      '30',
    ]);

    expect(result.exitCode, 0,
        reason: 'أداة توليد الترخيص الخارجية يجب أن تنجح: ${result.stderr}');

    final output = result.stdout as String;
    final codeLine = output
        .split('\n')
        .firstWhere((l) => l.trim().startsWith('SGV2-'));
    final code = codeLine.trim();

    final activation = await SubscriptionService.activateCode(code);

    expect(activation.isSuccess, true,
        reason: 'كود موقَّع رقمياً بشكل صحيح لنفس الجهاز يجب أن يُقبَل: '
            '${activation.message}');

    final sub = await SubscriptionService.getCurrentSubscription();
    expect(sub.isPaid, true);
    expect(sub.planInfo.nameAr, 'احترافي');
  });

  test(
      '🔴 كود مُوقَّع فعلياً بواسطة أداة Python لكن لجهاز مختلف تماماً '
      'يُرفَض (يثبت أن ربط الجهاز يعمل فعلياً في المسار الإنتاجي)',
      () async {
    // نولّد كوداً صحيحاً تماماً... لكن لجهاز عشوائي آخر غير هذا الجهاز
    final result = await Process.run('python3', [
      '/home/user/dev_tools/generate_license.py',
      '--device-id',
      'FFFFFFFFFFFFFFFF',
      '--plan',
      'SCHOOL',
      '--days',
      '9999',
    ]);
    expect(result.exitCode, 0);

    final output = result.stdout as String;
    final codeLine = output
        .split('\n')
        .firstWhere((l) => l.trim().startsWith('SGV2-'));
    final code = codeLine.trim();

    final activation = await SubscriptionService.activateCode(code);

    expect(activation.isSuccess, false,
        reason:
            'الكود صحيح رقمياً لكنه صادر لجهاز آخر، ويجب أن يُرفَض هنا');
  });

  test(
      '🔴 محاولة استخدام صيغة الكود القديمة المزوَّرة (الثغرة الأصلية) '
      'تُرفَض الآن تماماً بعد الترقية لـ RSA', () async {
    // إعادة تنفيذ نفس هجوم الـ PoC الأصلي (تزوير عبر hash متماثل قديم)
    // للتأكد من أن النظام الجديد يرفضه تلقائياً لأنه لا يطابق صيغة SGV2
    // الموقَّعة رقمياً على الإطلاق.
    const forgedOldStyleCode = 'SGV-SCHOOL-9999-9E081DB26C';

    final activation =
        await SubscriptionService.activateCode(forgedOldStyleCode);

    expect(activation.isSuccess, false,
        reason: 'صيغة الكود القديمة (SGV-...) لم تعد مدعومة إطلاقاً؛ '
            'فقط صيغة SGV2-... الموقَّعة رقمياً هي المقبولة الآن');
  });

  test('🔴 كود بصيغة SGV2 صحيحة شكلياً لكن بتوقيع مُلفَّق يدوياً يُرفَض',
      () async {
    final deviceId = await SubscriptionService.getDeviceId();
    // نبني كوداً بنفس الصيغة والبنية لكن بتوقيع عشوائي (محاولة تزوير
    // مباشرة لصيغة النظام الجديد نفسها، دون امتلاك المفتاح الخاص)
    const fakeSig =
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    final code = 'SGV2-SCHOOL-9999-${deviceId}0000-$fakeSig';

    final activation = await SubscriptionService.activateCode(code);

    expect(activation.isSuccess, false,
        reason: 'لا يمكن لأي طرف بدون المفتاح الخاص RSA توليد توقيع صالح، '
            'حتى لو طابقت الصيغة الشكلية للكود تماماً');
  });
}
