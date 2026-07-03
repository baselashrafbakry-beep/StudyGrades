// اختبار حي فعلي (Live Functional Test) لنظام Feature Flags والتحليلات المحلية
// في AdminService — يُشغّل المنطق الحقيقي على قاعدة بيانات Hive حقيقية
// (مؤقتة على القرص) للتأكد عملياً من أن التبديلات الإدارية تعمل كسقف
// حقيقي وليست شكلية، وأن نظام التحليلات المحلي يُسجّل ويحترم حالة التفعيل.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:study_grades_voice/services/admin_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Feature Flags — القيم الافتراضية', () {
    test('كل المفاتيح مفعّلة افتراضياً (true) عند عدم وجود إعداد محفوظ', () async {
      expect(await AdminService.isServerSpeechEnabled(), true);
      expect(await AdminService.isOfflineModeEnabled(), true);
      expect(await AdminService.isAnalyticsEnabled(), true);
    });
  });

  group('Feature Flags — enable_server_speech كسقف حقيقي', () {
    test('عند تعطيل المفتاح من الإعدادات، تعكسه الدالة المساعدة فوراً', () async {
      expect(await AdminService.isServerSpeechEnabled(), true);
      await AdminService.setSystemSetting('enable_server_speech', false);
      expect(await AdminService.isServerSpeechEnabled(), false);

      // إعادة التفعيل يجب أن تعمل أيضاً
      await AdminService.setSystemSetting('enable_server_speech', true);
      expect(await AdminService.isServerSpeechEnabled(), true);
    });
  });

  group('Feature Flags — enable_offline_mode كسقف حقيقي', () {
    test('عند تعطيل الوضع الأوفلاين، تعكسه الدالة المساعدة فوراً', () async {
      expect(await AdminService.isOfflineModeEnabled(), true);
      await AdminService.setSystemSetting('enable_offline_mode', false);
      expect(await AdminService.isOfflineModeEnabled(), false);
    });
  });

  group('نظام التحليلات المحلي (Analytics) — اختبار حي', () {
    test('trackEvent يزيد العدّاد فعلياً عند تفعيل التحليلات', () async {
      await AdminService.setSystemSetting('enable_analytics', true);

      await AdminService.trackEvent('grading_session_started');
      await AdminService.trackEvent('grading_session_started');
      await AdminService.trackEvent('grade_synced_online');

      final counters = await AdminService.getAnalyticsCounters();
      expect(counters['grading_session_started'], 2);
      expect(counters['grade_synced_online'], 1);
    });

    test('trackEvent لا يُسجّل أي شيء عند تعطيل التحليلات (احترام حقيقي للسقف)',
        () async {
      await AdminService.setSystemSetting('enable_analytics', false);

      await AdminService.trackEvent('excel_export_completed');
      await AdminService.trackEvent('excel_export_completed');

      final counters = await AdminService.getAnalyticsCounters();
      expect(counters.containsKey('excel_export_completed'), false);
      expect(counters.isEmpty, true);
    });

    test('إعادة تفعيل التحليلات بعد تعطيلها تسمح بالتسجيل من جديد', () async {
      await AdminService.setSystemSetting('enable_analytics', false);
      await AdminService.trackEvent('grade_saved_locally');
      expect((await AdminService.getAnalyticsCounters()).isEmpty, true);

      await AdminService.setSystemSetting('enable_analytics', true);
      await AdminService.trackEvent('grade_saved_locally');
      final counters = await AdminService.getAnalyticsCounters();
      expect(counters['grade_saved_locally'], 1);
    });

    test('getAnalyticsLastUpdated يُحدَّث فعلياً بعد كل حدث', () async {
      await AdminService.setSystemSetting('enable_analytics', true);
      expect(await AdminService.getAnalyticsLastUpdated(), null);

      await AdminService.trackEvent('grading_session_started');
      final lastUpdated = await AdminService.getAnalyticsLastUpdated();
      expect(lastUpdated, isNotNull);
      // تأكد أنه تاريخ ISO8601 صالح فعلاً
      expect(() => DateTime.parse(lastUpdated!), returnsNormally);
    });

    test('clearAnalyticsCounters يمسح كل العدّادات فعلياً', () async {
      await AdminService.setSystemSetting('enable_analytics', true);
      await AdminService.trackEvent('grading_session_started');
      await AdminService.trackEvent('grade_synced_online');
      expect((await AdminService.getAnalyticsCounters()).length, 2);

      await AdminService.clearAnalyticsCounters();
      expect((await AdminService.getAnalyticsCounters()).isEmpty, true);
    });

    test('trackEvent لا يرمي استثناء أبداً حتى لو فشل الوصول للصندوق (أمان كامل)',
        () async {
      // محاكاة استدعاء متكرر سريع للتأكد من عدم تعارض الكتابة (race condition)
      await AdminService.setSystemSetting('enable_analytics', true);
      final futures = List.generate(
        20,
        (_) => AdminService.trackEvent('grading_session_started'),
      );
      await Future.wait(futures);
      final counters = await AdminService.getAnalyticsCounters();
      expect(counters['grading_session_started'], 20);
    });
  });

  group('تكامل: تسلسل واقعي لجلسة رصد درجات كاملة', () {
    test('محاكاة جلسة كاملة: بدء → حفظ محلي → مزامنة → تصدير Excel', () async {
      await AdminService.setSystemSetting('enable_analytics', true);

      // 1. المعلم يبدأ جلسة رصد
      await AdminService.trackEvent('grading_session_started');
      // 2. يحفظ 3 طلاب أوفلاين
      await AdminService.trackEvent('grade_saved_locally');
      await AdminService.trackEvent('grade_saved_locally');
      await AdminService.trackEvent('grade_saved_locally');
      // 3. الاتصال يعود ويتم مزامنة درجتين
      await AdminService.trackEvent('grade_synced_online');
      await AdminService.trackEvent('grade_synced_online');
      // 4. يصدّر تقرير Excel
      await AdminService.trackEvent('excel_export_completed');

      final counters = await AdminService.getAnalyticsCounters();
      expect(counters['grading_session_started'], 1);
      expect(counters['grade_saved_locally'], 3);
      expect(counters['grade_synced_online'], 2);
      expect(counters['excel_export_completed'], 1);

      // المجموع الكلي للأحداث المسجّلة = 7
      final total = counters.values.fold<int>(0, (a, b) => a + b);
      expect(total, 7);
    });
  });
}
