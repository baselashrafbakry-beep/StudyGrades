// اختبار حي فعلي (Live Functional Test) لـ SubscriptionService.syncWithServer()
// — منطق "المصالحة" (Pull-based Reconciliation) الذي صُمِّم ليكون البديل
// العملي لتلقي Webhooks من بوابة الدفع Paymob مباشرةً داخل تطبيق Flutter
// (وهو أمر مستحيل معمارياً لأن Webhooks هي أحداث خادم-لخادم).
//
// يستخدم `SubscriptionService.debugServerFetchOverride` (نقطة حَقن
// للاختبار فقط، بنفس نمط `GradingProvider.debugSyncOverride` المُتَّبع في
// بقية المشروع) للتحكم الحتمي في استجابة "السيرفر" المُحاكاة دون أي اتصال
// شبكة فعلي أو حاجة لتشغيل Dio/mock adapter.
//
// يغطي بالتحديد سياسة الدمج (Merge Policy) الموثَّقة في تعليق الدالة:
//   أ) ترقية: السيرفر يُعلن خطة مدفوعة نشطة أحدث/مختلفة → تُطبَّق فوراً.
//   ب) إلغاء صريح: السيرفر يُعلن أن نفس الخطة المحلية لم تعد نشطة → تُطبَّق.
//   ج) أي حالة غامضة/غير متطابقة أخرى → لا تُطبَّق أبداً (أماناً أولاً).

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_grades_voice/models/subscription_model.dart';
import 'package:study_grades_voice/services/subscription_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_sync_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings_box');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    SubscriptionService.debugServerFetchOverride = null;
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> setLocalPlan(
    SubscriptionPlan plan, {
    required bool isActive,
    DateTime? expiryDate,
  }) async {
    final sub = UserSubscription(
      plan: plan,
      startDate: DateTime.now(),
      expiryDate: expiryDate,
      isActive: isActive,
      daysRemaining: expiryDate != null
          ? expiryDate.difference(DateTime.now()).inDays.clamp(0, 9999)
          : -1,
    );
    final box = Hive.box('settings_box');
    await box.put('subscription_data', jsonEncode(sub.toJson()));
  }

  group('SubscriptionService.syncWithServer — سيناريوهات آمنة (best-effort)',
      () {
    test('السيرفر لا يستجيب (null) => لا تحديث، ترجع false', () async {
      SubscriptionService.debugServerFetchOverride = () async => null;

      final updated = await SubscriptionService.syncWithServer();

      expect(updated, false);
      final sub = await SubscriptionService.getCurrentSubscription();
      expect(sub.plan, SubscriptionPlan.free);
    });

    test(
        'استثناء أثناء الاتصال (مثلاً انقطاع إنترنت) => يُمتَص بأمان، ترجع false',
        () async {
      SubscriptionService.debugServerFetchOverride =
          () async => throw Exception('محاكاة فشل شبكة');

      final updated = await SubscriptionService.syncWithServer();

      expect(updated, false);
      final sub = await SubscriptionService.getCurrentSubscription();
      expect(sub.plan, SubscriptionPlan.free);
    });

    test('صيغة استجابة فاسدة (بدون حقل plan) => تُتجاهَل بأمان، ترجع false',
        () async {
      SubscriptionService.debugServerFetchOverride = () async => {
            'is_active': true,
            'expiry_date':
                DateTime.now().add(const Duration(days: 30)).toIso8601String(),
          };

      final updated = await SubscriptionService.syncWithServer();

      expect(updated, false);
    });
  });

  group('SubscriptionService.syncWithServer — سياسة الترقية (Upgrade)', () {
    test(
        'اشتراك محلي مجاني + السيرفر يُعلن خطة "pro" مدفوعة نشطة => تُطبَّق فوراً (دفع Paymob ناجح)',
        () async {
      final expiryIso =
          DateTime.now().add(const Duration(days: 30)).toIso8601String();

      SubscriptionService.debugServerFetchOverride = () async => {
            'plan': 'pro',
            'is_active': true,
            'is_trial': false,
            'start_date': DateTime.now().toIso8601String(),
            'expiry_date': expiryIso,
          };

      final updated = await SubscriptionService.syncWithServer();

      expect(updated, true);
      final sub = await SubscriptionService.getCurrentSubscription();
      expect(sub.plan, SubscriptionPlan.pro);
      expect(sub.isActive, true);
      expect(sub.isPaid, true);
    });

    test(
        'اشتراك محلي "basic" + السيرفر يُعلن ترقية لـ "school" (نفس الخطة تغيّرت) => تُطبَّق',
        () async {
      await setLocalPlan(
        SubscriptionPlan.basic,
        isActive: true,
        expiryDate: DateTime.now().add(const Duration(days: 10)),
      );

      final expiryIso =
          DateTime.now().add(const Duration(days: 365)).toIso8601String();
      SubscriptionService.debugServerFetchOverride = () async => {
            'plan': 'school',
            'is_active': true,
            'expiry_date': expiryIso,
          };

      final updated = await SubscriptionService.syncWithServer();

      expect(updated, true);
      final sub = await SubscriptionService.getCurrentSubscription();
      expect(sub.plan, SubscriptionPlan.school);
    });

    test(
        'نفس الخطة المحلية ونفس تاريخ الانتهاء تماماً (لا تغيير فعلي) => لا تحديث، ترجع false',
        () async {
      final expiryDate = DateTime.now().add(const Duration(days: 30));
      final expiryIso = expiryDate.toIso8601String();

      // نخزّن الاشتراك المحلي بنفس الـ ISO string لضمان تطابق الدقة
      // الزمنية (microseconds) بعد جولة full round-trip عبر JSON.
      final localExpiry = DateTime.parse(expiryIso);
      await setLocalPlan(
        SubscriptionPlan.pro,
        isActive: true,
        expiryDate: localExpiry,
      );

      SubscriptionService.debugServerFetchOverride = () async => {
            'plan': 'pro',
            'is_active': true,
            'expiry_date': expiryIso,
          };

      final updated = await SubscriptionService.syncWithServer();

      expect(updated, false);
    });

    test(
        'السيرفر يُعلن خطة "free" (غير مدفوعة) بينما المحلي "pro" نشط => لا تُطبَّق (حماية من تصفير خاطئ)',
        () async {
      await setLocalPlan(
        SubscriptionPlan.pro,
        isActive: true,
        expiryDate: DateTime.now().add(const Duration(days: 30)),
      );

      SubscriptionService.debugServerFetchOverride = () async => {
            'plan': 'free',
            'is_active': true,
          };

      final updated = await SubscriptionService.syncWithServer();

      expect(updated, false);
      final sub = await SubscriptionService.getCurrentSubscription();
      expect(sub.plan, SubscriptionPlan.pro); // بقي كما هو محلياً
    });
  });

  group(
      'SubscriptionService.syncWithServer — سياسة الإلغاء الصريح (Deactivation)',
      () {
    test(
        'اشتراك محلي "pro" نشط + السيرفر يُعلن نفس الخطة "pro" لكن is_active=false => تُطبَّق (إلغاء/فشل دفع متكرر)',
        () async {
      await setLocalPlan(
        SubscriptionPlan.pro,
        isActive: true,
        expiryDate: DateTime.now().add(const Duration(days: 30)),
      );

      SubscriptionService.debugServerFetchOverride = () async => {
            'plan': 'pro',
            'is_active': false,
          };

      final updated = await SubscriptionService.syncWithServer();

      expect(updated, true);
    });

    test(
        'اشتراك محلي "pro" نشط + السيرفر يُعلن خطة مختلفة "basic" غير نشطة => لا تُطبَّق (لا علاقة بالخطة المحلية الحالية)',
        () async {
      await setLocalPlan(
        SubscriptionPlan.pro,
        isActive: true,
        expiryDate: DateTime.now().add(const Duration(days: 30)),
      );

      SubscriptionService.debugServerFetchOverride = () async => {
            'plan': 'basic',
            'is_active': false,
          };

      final updated = await SubscriptionService.syncWithServer();

      expect(updated, false);
      final sub = await SubscriptionService.getCurrentSubscription();
      expect(sub.plan, SubscriptionPlan.pro); // بقي كما هو
    });

    test(
        'اشتراك محلي مجاني (غير مدفوع) + السيرفر يُعلن is_active=false لخطة "free" => لا تُطبَّق (localSub.isPaid == false أصلاً)',
        () async {
      SubscriptionService.debugServerFetchOverride = () async => {
            'plan': 'free',
            'is_active': false,
          };

      final updated = await SubscriptionService.syncWithServer();

      expect(updated, false);
    });
  });
}
