// اختبار حي فعلي (Live Functional Test) للتحقق من أن نظام فرض ميزات
// الاشتراك (SubscriptionService.hasFeature) يعمل فعلياً على قاعدة بيانات
// Hive حقيقية (مؤقتة على القرص)، وأنه يعكس بدقة مصفوفة الميزات المعرَّفة
// في SubscriptionPlans لكل خطة (free/basic/pro/school).
//
// هذا الاختبار يغلق الفجوة المكتشَفة سابقاً: hasFeature() كانت "كوداً
// ميتاً" غير مستخدَم فعلياً من أي شاشة، وتم للتو ربطها في grading_screen.dart
// (تصدير Excel + فتح لوحة التحليلات). هذا الاختبار يتحقق أن الدالة نفسها
// تُرجع القيم الصحيحة تماماً بحسب الخطة الحالية المخزَّنة محلياً.

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:study_grades_voice/models/subscription_model.dart';
import 'package:study_grades_voice/services/subscription_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_sub_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings_box');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// يحفظ اشتراكاً وهمياً بخطة معيّنة مباشرة في Hive (نفس الآلية
  /// التي يستخدمها SubscriptionService._saveSubscription داخلياً)
  Future<void> setPlan(SubscriptionPlan plan) async {
    final sub = UserSubscription(
      plan: plan,
      startDate: DateTime.now(),
      expiryDate: DateTime.now().add(const Duration(days: 30)),
      isActive: true,
      daysRemaining: 30,
    );
    final box = Hive.box('settings_box');
    await box.put('subscription_data', jsonEncode(sub.toJson()));
  }

  group('SubscriptionService.hasFeature — خطة مجانية (free)', () {
    test('لا تملك export_excel ولا analytics ولا export_csv', () async {
      // لا اشتراك محفوظ إطلاقاً → يجب أن يعود للـ free تلقائياً
      expect(await SubscriptionService.hasFeature('export_excel'), false);
      expect(await SubscriptionService.hasFeature('analytics'), false);
      expect(await SubscriptionService.hasFeature('export_csv'), false);
      expect(await SubscriptionService.hasFeature('admin_panel'), false);
      // لكن الإدخال الصوتي متاح حتى في المجاني
      expect(await SubscriptionService.hasFeature('voice_input'), true);
    });
  });

  group('SubscriptionService.hasFeature — خطة أساسي (basic)', () {
    test('تملك analytics و export_csv لكن ليس export_excel', () async {
      await setPlan(SubscriptionPlan.basic);
      expect(await SubscriptionService.hasFeature('analytics'), true);
      expect(await SubscriptionService.hasFeature('export_csv'), true);
      expect(await SubscriptionService.hasFeature('export_excel'), false);
      expect(await SubscriptionService.hasFeature('admin_panel'), false);
    });
  });

  group('SubscriptionService.hasFeature — خطة احترافي (pro)', () {
    test('تملك export_excel و analytics و priority_support', () async {
      await setPlan(SubscriptionPlan.pro);
      expect(await SubscriptionService.hasFeature('export_excel'), true);
      expect(await SubscriptionService.hasFeature('analytics'), true);
      expect(await SubscriptionService.hasFeature('priority_support'), true);
      // لوحة التحكم الإدارية لا تزال حصراً لخطة المدرسة
      expect(await SubscriptionService.hasFeature('admin_panel'), false);
    });
  });

  group('SubscriptionService.hasFeature — خطة مدرسة (school)', () {
    test('تملك كل الميزات بلا استثناء بما فيها admin_panel', () async {
      await setPlan(SubscriptionPlan.school);
      expect(await SubscriptionService.hasFeature('export_excel'), true);
      expect(await SubscriptionService.hasFeature('analytics'), true);
      expect(await SubscriptionService.hasFeature('export_csv'), true);
      expect(await SubscriptionService.hasFeature('offline_sync'), true);
      expect(await SubscriptionService.hasFeature('admin_panel'), true);
      expect(await SubscriptionService.hasFeature('priority_support'), true);
      expect(await SubscriptionService.hasFeature('voice_input'), true);
    });
  });

  group('SubscriptionService.hasFeature — مفتاح غير معروف', () {
    test('يُرجع false افتراضياً لأي اسم ميزة غير معرَّف', () async {
      await setPlan(SubscriptionPlan.school);
      expect(await SubscriptionService.hasFeature('non_existent_feature'), false);
    });
  });

  group('SubscriptionService.hasFeature — اشتراك منتهي الصلاحية', () {
    test('يعود تلقائياً لخطة free (بلا export_excel) بعد الانتهاء', () async {
      final expiredSub = UserSubscription(
        plan: SubscriptionPlan.pro,
        startDate: DateTime.now().subtract(const Duration(days: 60)),
        expiryDate: DateTime.now().subtract(const Duration(days: 1)),
        isActive: true,
        daysRemaining: -1,
      );
      final box = Hive.box('settings_box');
      await box.put('subscription_data', jsonEncode(expiredSub.toJson()));

      // getCurrentSubscription يتحقق من isExpired ويعيد free تلقائياً
      final current = await SubscriptionService.getCurrentSubscription();
      expect(current.plan, SubscriptionPlan.free);
      expect(await SubscriptionService.hasFeature('export_excel'), false);
    });
  });
}
