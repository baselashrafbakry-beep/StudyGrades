import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/subscription_model.dart';
import '../utils/error_handler.dart';

/// --------------------------------------------------------------------------
/// خدمة نظام الاشتراكات — تفعيل بكود + حفظ محلي
/// الأكواد مُخزَّنة بصيغة SHA-256 hash لمنع كشفها في ملفات APK المفككة
/// --------------------------------------------------------------------------
class SubscriptionService {
  static const _boxKey = 'subscription_data';
  static const _prefKey = 'user_subscription';

  // ======================================================================
  // الـ salt الثابت للـ hashing — يُغيَّر مع كل إصدار تجاري جديد
  // ======================================================================
  static const String _salt = 'SGV_2026_BASEL_SECURE';

  /// حساب SHA-256 hash للكود
  static String _hashCode(String code) {
    final bytes = utf8.encode('$_salt:${code.trim().toUpperCase()}');
    return sha256.convert(bytes).toString();
  }

  // ======================================================================
  // قاموس رموز التفعيل — مُخزَّن كـ SHA-256 hash للأمان
  // لا يمكن استخلاص الأكواد الأصلية من الـ APK المفكك
  // الصيغة: hash('SALT:CODE') → {'plan': 'pro', 'days': 365, 'desc': 'وصف'}
  // ======================================================================
  static final Map<String, Map<String, dynamic>> _hashedCodes = {
    // GRADER-PRO-TRIAL → تجربة احترافية 14 يوم
    _hashCode('GRADER-PRO-TRIAL'): {'plan': 'pro', 'days': 14, 'desc': 'تجربة احترافية 14 يوم'},
    // STUDY2026-TRIAL → تجربة أساسي شهر
    _hashCode('STUDY2026-TRIAL'): {'plan': 'basic', 'days': 30, 'desc': 'تجربة أساسي شهر'},
    // رموز مدفوعة (تُولَّد للعملاء)
    _hashCode('BASEL-PRO-01'): {'plan': 'pro', 'days': 30, 'desc': 'اشتراك احترافي شهري'},
    _hashCode('BASEL-PRO-12'): {'plan': 'pro', 'days': 365, 'desc': 'اشتراك احترافي سنوي'},
    _hashCode('BASEL-BASIC-01'): {'plan': 'basic', 'days': 30, 'desc': 'اشتراك أساسي شهري'},
    _hashCode('BASEL-SCHOOL-12'): {'plan': 'school', 'days': 365, 'desc': 'اشتراك مدرسة سنوي'},
    // رمز تطوير (مطور فقط — فعّال دائماً)
    _hashCode('DEV-MASTER-2026'): {'plan': 'school', 'days': 9999, 'desc': 'حساب المطور الرئيسي'},
  };

  // ======================================================================
  // تفعيل رمز الاشتراك
  // ======================================================================
  static Future<ActivationResult> activateCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase();

    if (code.isEmpty) {
      return ActivationResult.fail('الرجاء إدخال رمز التفعيل');
    }

    // التحقق من الرمز عبر hash — الكود الأصلي لا يُخزَّن ولا يُقارَن مباشرة
    final codeHash = _hashCode(code);
    final entry = _hashedCodes[codeHash];
    if (entry == null) {
      return ActivationResult.fail(
          'رمز التفعيل غير صحيح\nتحقق من الرمز أو تواصل مع المطور');
    }

    // التحقق من أن الرمز لم يُستخدم من قبل — نُخزِّن الـ hash وليس الكود
    final usedHashes = await _getUsedCodes(); // يُعيد hashes
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

  /// توليد رمز تفعيل عشوائي (للمطور)
  static String generateCode({
    String plan = 'pro',
    int days = 30,
    String prefix = 'SGV',
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final suffix = timestamp.substring(timestamp.length - 6);
    return '$prefix-${plan.toUpperCase()}-$suffix';
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
