import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/subscription_model.dart';
import '../utils/error_handler.dart';

/// --------------------------------------------------------------------------
/// خدمة نظام الاشتراكات — تفعيل بكود + حفظ محلي
/// --------------------------------------------------------------------------
class SubscriptionService {
  static const _boxKey = 'subscription_data';
  static const _prefKey = 'user_subscription';

  // ======================================================================
  // قاموس رموز التفعيل — يمكن توليد رموز جديدة وإضافتها هنا
  // الصيغة: 'CODE' → {'plan': 'pro', 'days': 365, 'desc': 'وصف'}
  // ======================================================================
  static const Map<String, Map<String, dynamic>> _validCodes = {
    // رموز تجريبية للاختبار (14 يوم Pro مجاناً)
    'GRADER-PRO-TRIAL': {'plan': 'pro', 'days': 14, 'desc': 'تجربة احترافية 14 يوم'},
    'STUDY2026-TRIAL': {'plan': 'basic', 'days': 30, 'desc': 'تجربة أساسي شهر'},
    // رموز مدفوعة (تُولَّد للعملاء)
    'BASEL-PRO-01': {'plan': 'pro', 'days': 30, 'desc': 'اشتراك احترافي شهري'},
    'BASEL-PRO-12': {'plan': 'pro', 'days': 365, 'desc': 'اشتراك احترافي سنوي'},
    'BASEL-BASIC-01': {'plan': 'basic', 'days': 30, 'desc': 'اشتراك أساسي شهري'},
    'BASEL-SCHOOL-12': {'plan': 'school', 'days': 365, 'desc': 'اشتراك مدرسة سنوي'},
    // رمز تطوير (مطور فقط — فعّال دائماً)
    'DEV-MASTER-2026': {'plan': 'school', 'days': 9999, 'desc': 'حساب المطور الرئيسي'},
  };

  // ======================================================================
  // تفعيل رمز الاشتراك
  // ======================================================================
  static Future<ActivationResult> activateCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase();

    if (code.isEmpty) {
      return ActivationResult.fail('الرجاء إدخال رمز التفعيل');
    }

    // التحقق من الرمز
    final entry = _validCodes[code];
    if (entry == null) {
      return ActivationResult.fail(
          'رمز التفعيل غير صحيح\nتحقق من الرمز أو تواصل مع المطور');
    }

    // التحقق من أن الرمز لم يُستخدم من قبل (تجنب إعادة الاستخدام)
    final usedCodes = await _getUsedCodes();
    if (usedCodes.contains(code) && code != 'DEV-MASTER-2026') {
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
      // محاولة القراءة من Hive أولاً
      if (Hive.isBoxOpen('settings')) {
        final box = Hive.box('settings');
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
      if (Hive.isBoxOpen('settings')) {
        Hive.box('settings').put(_boxKey, json);
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

  static Future<void> _markCodeUsed(String code) async {
    try {
      final codes = await _getUsedCodes();
      codes.add(code);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'used_activation_codes', jsonEncode(codes.toList()));
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
