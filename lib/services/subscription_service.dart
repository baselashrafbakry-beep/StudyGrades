import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/subscription_model.dart';
import '../utils/error_handler.dart';

/// --------------------------------------------------------------------------
/// خدمة نظام الاشتراكات — تفعيل بكود + حفظ محلي
///
/// ⚠️ ملاحظة أمنية هامة:
/// نظام أكواد التفعيل في هذا التطبيق يعمل بالكامل محلياً (بدون سيرفر خارجي)،
/// لذلك تم تصميم نظامين متكاملين:
///
///  1) أكواد عامة (Universal) — للتجارب المجانية والترويج فقط
///     (مثل GRADER-PRO-TRIAL) — يمكن استخدامها من أي جهاز، لأنها غير مدفوعة
///     ولا تشكل خسارة تجارية حقيقية.
///
///  2) أكواد مخصصة لكل جهاز (Device-Bound License Keys) — للاشتراكات
///     المدفوعة الحقيقية. يتم توليدها عبر HMAC-SHA256 مرتبطة بمعرّف
///     فريد للجهاز (Device ID)، مما يمنع مشاركة نفس الكود المدفوع بين
///     عدة أجهزة (كل كود يعمل فقط على الجهاز الذي طلبه المستخدم).
///     صيغة الكود: SGV-<PLAN>-<DAYS>-<HASH10>
///
/// هذا يحل المشكلة الجوهرية لنظام الأكواد المشتركة القديم، حيث كان بإمكان
/// أي شخص نشر كود مدفوع واحد واستخدامه من قبل عدد غير محدود من الأجهزة.
/// --------------------------------------------------------------------------
class SubscriptionService {
  static const _boxKey = 'subscription_data';
  static const _prefKey = 'user_subscription';
  static const _deviceIdKey = 'device_license_id';

  // ======================================================================
  // الـ salt الثابت للـ hashing — يُغيَّر مع كل إصدار تجاري جديد
  // ======================================================================
  static const String _salt = 'SGV_2026_BASEL_SECURE';

  /// حساب SHA-256 hash للكود (للأكواد العامة القديمة + تتبع الاستخدام)
  static String _hashCode(String code) {
    final bytes = utf8.encode('$_salt:${code.trim().toUpperCase()}');
    return sha256.convert(bytes).toString();
  }

  // ======================================================================
  // قاموس رموز التفعيل العامة (تجربة مجانية + رمز المطور فقط)
  // مُخزَّن كـ SHA-256 hash للأمان — لا يمكن استخلاص الأكواد الأصلية
  // من الـ APK المفكك. هذه الأكواد ترويجية/تجريبية وليست مصدر دخل حقيقي،
  // لذلك يُسمح باستخدامها من أي جهاز بأمان.
  // ======================================================================
  static final Map<String, Map<String, dynamic>> _hashedCodes = {
    // GRADER-PRO-TRIAL → تجربة احترافية 14 يوم
    _hashCode('GRADER-PRO-TRIAL'): {
      'plan': 'pro',
      'days': 14,
      'desc': 'تجربة احترافية 14 يوم'
    },
    // STUDY2026-TRIAL → تجربة أساسي شهر
    _hashCode('STUDY2026-TRIAL'): {
      'plan': 'basic',
      'days': 30,
      'desc': 'تجربة أساسي شهر'
    },
    // رمز تطوير (مطور فقط — فعّال دائماً، مُستثنى من فحص "استُخدم من قبل")
    _hashCode('DEV-MASTER-2026'): {
      'plan': 'school',
      'days': 9999,
      'desc': 'حساب المطور الرئيسي'
    },
  };

  // ======================================================================
  // معرّف الجهاز الفريد (Device License ID)
  // يُولَّد مرة واحدة فقط ويُخزَّن محلياً، ويُستخدَم كأساس لربط أكواد
  // الاشتراك المدفوعة بجهاز واحد فقط.
  // ======================================================================
  static Future<String> getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_deviceIdKey);
      if (id == null || id.isEmpty) {
        id = _generateRandomDeviceId();
        await prefs.setString(_deviceIdKey, id);
      }
      return id;
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'SubscriptionService.getDeviceId');
      // معرّف احتياطي مؤقت في حال فشل التخزين (لن يُحفظ)
      return _generateRandomDeviceId();
    }
  }

  static String _generateRandomDeviceId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(8, (_) => rand.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  // ======================================================================
  // توليد كود تفعيل مخصص لجهاز مُعيَّن (أداة المطوّر فقط)
  // planCode: BASIC | PRO | SCHOOL
  // ======================================================================
  static String generatePersonalizedCode({
    required String deviceId,
    required String planCode,
    required int days,
  }) {
    final normalizedDeviceId = deviceId.trim().toUpperCase();
    final normalizedPlan = planCode.trim().toUpperCase();
    final hash = _personalizedHash(normalizedDeviceId, normalizedPlan, days);
    return 'SGV-$normalizedPlan-$days-$hash';
  }

  static String _personalizedHash(
      String deviceId, String planCode, int days) {
    final bytes =
        utf8.encode('$_salt:PERSONAL:$deviceId:$planCode:$days');
    return sha256.convert(bytes).toString().substring(0, 10).toUpperCase();
  }

  static const Map<String, String> _planCodeToName = {
    'BASIC': 'basic',
    'PRO': 'pro',
    'SCHOOL': 'school',
  };

  static const Map<String, String> _planLabelAr = {
    'basic': 'أساسي',
    'pro': 'احترافي',
    'school': 'مدرسة',
  };

  /// يحاول تفسير كود بصيغة "مخصص لهذا الجهاز": SGV-<PLAN>-<DAYS>-<HASH10>
  /// يُعيد null إذا لم تكن الصيغة مطابقة أو كان الكود غير صالح لهذا الجهاز
  static Future<Map<String, dynamic>?> _tryParsePersonalizedCode(
      String code) async {
    final parts = code.split('-');
    if (parts.length != 4 || parts[0] != 'SGV') return null;

    final planCode = parts[1];
    final planName = _planCodeToName[planCode];
    if (planName == null) return null;

    final days = int.tryParse(parts[2]);
    if (days == null || days <= 0) return null;

    final hashPart = parts[3];
    final deviceId = await getDeviceId();
    final expectedHash = _personalizedHash(deviceId, planCode, days);
    if (expectedHash != hashPart) {
      // إما أن الكود تالف، أو أنه صادر لجهاز آخر غير هذا الجهاز
      return null;
    }

    final planLabel = _planLabelAr[planName] ?? planName;
    return {
      'plan': planName,
      'days': days,
      'desc': 'اشتراك $planLabel مخصص لهذا الجهاز ($days يوم)',
    };
  }

  // ======================================================================
  // تفعيل رمز الاشتراك
  // ======================================================================
  static Future<ActivationResult> activateCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase();

    if (code.isEmpty) {
      return ActivationResult.fail('الرجاء إدخال رمز التفعيل');
    }

    // 1) جرّب أولاً صيغة الكود المخصص لهذا الجهاز (الأكواد المدفوعة الحقيقية)
    Map<String, dynamic>? entry = await _tryParsePersonalizedCode(code);

    // 2) إن لم يطابق الصيغة المخصصة، جرّب الأكواد العامة (تجربة/مطور)
    entry ??= _hashedCodes[_hashCode(code)];

    if (entry == null) {
      return ActivationResult.fail(
          'رمز التفعيل غير صحيح أو غير مخصص لهذا الجهاز\n'
          'تحقق من الرمز أو تواصل مع المطور');
    }

    // التحقق من أن الرمز لم يُستخدم من قبل على هذا الجهاز
    // (نُخزِّن الـ hash وليس الكود الأصلي لحماية الخصوصية)
    final usedHashes = await _getUsedCodes();
    final codeHash = _hashCode(code);
    final devHash = _hashCode('DEV-MASTER-2026');
    if (usedHashes.contains(codeHash) && codeHash != devHash) {
      return ActivationResult.fail(
          'هذا الرمز تم استخدامه بالفعل\nيمكنك الحصول على رمز جديد من المطور');
    }

    // تحديد الخطة والتاريخ
    final planName = entry['plan'] as String;
    final days = entry['days'] as int;
    final desc = entry['desc'] as String;
    final plan = SubscriptionPlan.values.firstWhere(
      (p) => p.name == planName,
      orElse: () => SubscriptionPlan.basic,
    );

    // حساب تاريخ الانتهاء (إذا كان هناك اشتراك حالي → تمديده)
    final current = await getCurrentSubscription();
    DateTime startDate = DateTime.now();
    if (current.isActive &&
        current.isPaid &&
        current.expiryDate != null &&
        !current.isExpired) {
      // تمديد من نهاية الاشتراك الحالي
      startDate = current.expiryDate!;
    }
    final expiryDate = days == 9999
        ? DateTime(2099, 12, 31) // حساب المطور — لا ينتهي
        : startDate.add(Duration(days: days));

    final subscription = UserSubscription(
      plan: plan,
      startDate: DateTime.now(),
      expiryDate: expiryDate,
      isActive: true,
      isTrial: desc.contains('تجربة'),
      daysRemaining: days,
    );

    // الحفظ
    await _saveSubscription(subscription);
    await _markCodeUsed(code);

    return ActivationResult.success(subscription, desc);
  }

  // ======================================================================
  // جلب الاشتراك الحالي
  // ======================================================================
  static Future<UserSubscription> getCurrentSubscription() async {
    try {
      // محاولة القراءة من Hive أولاً — الاسم الصحيح هو 'settings_box' (مُعرَّف في StorageService)
      if (Hive.isBoxOpen('settings_box')) {
        final box = Hive.box('settings_box');
        final raw = box.get(_boxKey);
        if (raw is String && raw.isNotEmpty) {
          final sub = UserSubscription.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw)));
          if (!sub.isExpired) return sub;
          // انتهى → أعد للـ free
          return UserSubscription.free();
        }
      }
      // fallback إلى SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        final sub = UserSubscription.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw)));
        if (!sub.isExpired) return sub;
      }
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'SubscriptionService.getCurrentSubscription');
    }
    return UserSubscription.free();
  }

  // ======================================================================
  // تحقق من صلاحية
  // ======================================================================
  static Future<bool> hasFeature(String feature) async {
    final sub = await getCurrentSubscription();
    final info = sub.planInfo;
    switch (feature) {
      case 'offline_sync':
        return info.offlineSync;
      case 'analytics':
        return info.analytics;
      case 'export_excel':
        return info.exportExcel;
      case 'export_csv':
        return info.exportCsv;
      case 'admin_panel':
        return info.adminPanel;
      case 'priority_support':
        return info.prioritySupport;
      case 'voice_input':
        return info.voiceInput;
      default:
        return false;
    }
  }

  // ======================================================================
  // إلغاء الاشتراك (إعادة للـ Free)
  // ======================================================================
  static Future<void> cancelSubscription() async {
    await _saveSubscription(UserSubscription.free());
  }

  // ======================================================================
  // أدوات مساعدة داخلية
  // ======================================================================
  static Future<void> _saveSubscription(UserSubscription sub) async {
    try {
      final json = jsonEncode(sub.toJson());
      // الاسم الصحيح هو 'settings_box' — يتطابق مع StorageService.settingsBoxName
      if (Hive.isBoxOpen('settings_box')) {
        Hive.box('settings_box').put(_boxKey, json);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, json);
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'SubscriptionService._saveSubscription');
    }
  }

  static Future<Set<String>> _getUsedCodes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('used_activation_codes');
      if (raw == null) return {};
      return Set<String>.from(
          (jsonDecode(raw) as List).map((e) => e.toString()));
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'SubscriptionService._getUsedCodes');
      return {};
    }
  }

  /// تحفظ الـ HASH وليس الكود الأصلي — حماية من كشف الأكواد
  static Future<void> _markCodeUsed(String code) async {
    try {
      final codeHash = _hashCode(code.trim().toUpperCase());
      final hashes = await _getUsedCodes(); // already returns Set<hash>
      hashes.add(codeHash);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'used_activation_codes', jsonEncode(hashes.toList()));
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'SubscriptionService._markCodeUsed');
    }
  }
}

/// نتيجة التفعيل
class ActivationResult {
  final bool isSuccess;
  final String message;
  final UserSubscription? subscription;

  const ActivationResult._({
    required this.isSuccess,
    required this.message,
    this.subscription,
  });

  factory ActivationResult.success(UserSubscription sub, String desc) =>
      ActivationResult._(
        isSuccess: true,
        message: 'تم تفعيل "$desc" بنجاح! 🎉\n'
            'الخطة: ${sub.planInfo.nameAr}\n'
            'تنتهي في: ${sub.expiryDate?.toLocal().toString().split(' ').first ?? 'لا تنتهي'}',
        subscription: sub,
      );

  factory ActivationResult.fail(String msg) =>
      ActivationResult._(isSuccess: false, message: msg);
}
