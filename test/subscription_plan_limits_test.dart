// اختبار حي فعلي (Live Functional Test) لفرض حدود الخطة الخاصة بعدد
// الفصول الدراسية (maxClassesPerTeacher) وعدد الطلاب بالفصل الواحد
// (maxStudentsPerClass) — يتحقق أن SubscriptionService.canOpenClass /
// markClassOpened / getMaxStudentsPerClass تعمل فعلياً على تخزين حقيقي
// (Hive + SharedPreferences مؤقتين)، وليست مجرد أرقام تسويقية معروضة في
// شاشة الأسعار بلا أي أثر فعلي.

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
    tempDir = await Directory.systemTemp.createTemp('hive_test_limits_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings_box');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

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

  group('SubscriptionService.canOpenClass — حد عدد الفصول (maxClassesPerTeacher)', () {
    test('فصل العرض التجريبي (classId=0) مسموح دائماً بلا قيود', () async {
      await setPlan(SubscriptionPlan.free); // maxClassesPerTeacher = 2
      expect(await SubscriptionService.canOpenClass(0), true);
    });

    test('خطة مجاني (حد فصلين): يُسمح بفتح أول فصلين فقط', () async {
      await setPlan(SubscriptionPlan.free); // maxClassesPerTeacher = 2
      expect(await SubscriptionService.canOpenClass(101), true);
      await SubscriptionService.markClassOpened(101);

      expect(await SubscriptionService.canOpenClass(102), true);
      await SubscriptionService.markClassOpened(102);

      // الفصل الثالث الجديد يجب أن يُرفض
      expect(await SubscriptionService.canOpenClass(103), false);

      // لكن فصل سبق فتحه يبقى متاحاً دائماً (لا يُعاد حسابه كفصل جديد)
      expect(await SubscriptionService.canOpenClass(101), true);
    });

    test('markClassOpened لا يُسجّل نفس الفصل مرتين', () async {
      await setPlan(SubscriptionPlan.free);
      await SubscriptionService.markClassOpened(201);
      await SubscriptionService.markClassOpened(201);
      expect(await SubscriptionService.getOpenedClassesCount(), 1);
    });

    test('باقة احترافي (فصول غير محدودة): لا يوجد أي رفض إطلاقاً', () async {
      await setPlan(SubscriptionPlan.pro); // maxClassesPerTeacher = -1
      for (var i = 1; i <= 10; i++) {
        expect(await SubscriptionService.canOpenClass(i), true);
        await SubscriptionService.markClassOpened(i);
      }
      expect(await SubscriptionService.getOpenedClassesCount(), 10);
    });

    test('خطة أساسي (حد 5 فصول): الفصل السادس الجديد يُرفض', () async {
      await setPlan(SubscriptionPlan.basic); // maxClassesPerTeacher = 5
      for (var i = 1; i <= 5; i++) {
        expect(await SubscriptionService.canOpenClass(i), true);
        await SubscriptionService.markClassOpened(i);
      }
      expect(await SubscriptionService.canOpenClass(6), false);
    });
  });

  group('SubscriptionService.getMaxStudentsPerClass — حد عدد الطلاب', () {
    test('خطة مجاني تُرجع 30', () async {
      await setPlan(SubscriptionPlan.free);
      expect(await SubscriptionService.getMaxStudentsPerClass(), 30);
    });

    test('خطة أساسي تُرجع 50', () async {
      await setPlan(SubscriptionPlan.basic);
      expect(await SubscriptionService.getMaxStudentsPerClass(), 50);
    });

    test('خطة احترافي تُرجع -1 (غير محدود)', () async {
      await setPlan(SubscriptionPlan.pro);
      expect(await SubscriptionService.getMaxStudentsPerClass(), -1);
    });

    test('خطة مدرسة تُرجع -1 (غير محدود)', () async {
      await setPlan(SubscriptionPlan.school);
      expect(await SubscriptionService.getMaxStudentsPerClass(), -1);
    });
  });
}
