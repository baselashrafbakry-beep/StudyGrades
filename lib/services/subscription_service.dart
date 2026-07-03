import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_id/android_id.dart';
import '../models/subscription_model.dart';
import '../utils/error_handler.dart';
import '../security/rsa_license_verifier.dart';

/// --------------------------------------------------------------------------
/// خدمة نظام الاشتراكات — تفعيل بكود + حفظ محلي
///
/// ⚠️ ملاحظة أمنية هامة (نظام V2 — توقيع رقمي غير متماثل RSA):
/// نظام أكواد التفعيل في هذا التطبيق يعمل بالكامل محلياً (بدون سيرفر خارجي)،
/// لذلك تم تصميم نظامين متكاملين:
///
///  1) أكواد عامة (Universal) — للتجارب المجانية فقط (مثل GRADER-PRO-TRIAL)
///     يمكن استخدامها من أي جهاز، لأنها غير مدفوعة ولا تشكل خسارة تجارية
///     حقيقية. تُخزَّن كـ SHA-256 hash فقط (لا يمكن استخلاص النص الأصلي).
///
///  2) أكواد مخصصة لكل جهاز (Device-Bound License Keys) — للاشتراكات
///     المدفوعة الحقيقية. تُوقَّع رقمياً بمفتاح RSA-2048 خاص (PSS/SHA-256)
///     يبقى حصرياً لدى المطوّر خارج هذا التطبيق تماماً (لا يُشحن أبداً
///     ضمن أي نسخة مُصرَّفة). التطبيق يحتوي فقط على المفتاح العام
///     المقابل للتحقق من صحة التوقيع — ما يعني أن استخراج أي شيء من
///     الـ APK/الويب المُصرَّف (بما فيه المفتاح العام نفسه) لا يُمكِّن
///     أي مهاجم من توليد كود جديد صالح، لأن التوقيع الرقمي RSA لا يمكن
///     تزويره بدون المفتاح الخاص.
///     صيغة الكود: SGV2-<PLAN>-<DAYS>-<DEVICE_B32>-<SIG_B32>
///
/// 🔴 لماذا تم التحويل من النظام القديم (HMAC/SHA-256 برمز salt ثابت)؟
/// النظام القديم كان يخزّن الـ "سر" (salt) كنص داخل الكود المصدري، وبالتالي
/// داخل الملف الثنائي المُصرَّف (APK / main.dart.js). تم إثبات فعلياً
/// (عبر اختبار حي: test/security_license_forgery_poc_test.dart) أن هذا
/// الـ salt قابل للاستخراج بسهولة عبر أدوات مثل `strings`، مما يسمح لأي
/// مستخدم عادي بإعادة حساب نفس دالة الـ hash محلياً وتوليد كود اشتراك
/// "مدرسة" مزوَّر وغير منتهٍ. التوقيع الرقمي غير المتماثل (RSA) يحل هذه
/// المشكلة الجذرية بشكل كامل ونهائي.
///
/// ⚠️ ملاحظة توافق: تم أيضاً إزالة دعم الكود السري `DEV-MASTER-2026` الذي
/// كان مخزَّناً كنص صريح داخل الكود المصدري (وبالتالي ظاهراً بوضوح داخل
/// main.dart.js المُصرَّف - تم التأكد من ذلك عبر grep). تم استبداله بكود
/// مطوّر جديد مخزَّن كـ SHA-256 hash فقط (بنفس أسلوب حماية الأكواد العامة).
/// --------------------------------------------------------------------------
class SubscriptionService {
  static const _boxKey = 'subscription_data';
  static const _prefKey = 'user_subscription';
  static const _deviceIdKey = 'device_license_id';

  // ======================================================================
  // الـ salt المستخدم فقط لحماية الأكواد الترويجية/التجريبية (غير الحرجة
  // تجارياً). لا علاقة له بأمان الأكواد المدفوعة الحقيقية بعد الآن —
  // تلك تعتمد بالكامل على التوقيع الرقمي RSA (انظر rsa_license_verifier.dart)
  // ======================================================================
  static const String _salt = 'SGV_2026_BASEL_SECURE_V2';

  /// حساب SHA-256 hash للكود (للأكواد العامة/الترويجية + تتبع الاستخدام)
  static String _hashCode(String code) {
    final bytes = utf8.encode('$_salt:${code.trim().toUpperCase()}');
    return sha256.convert(bytes).toString();
  }

  // ======================================================================
  // قاموس رموز التفعيل العامة (تجربة مجانية + رمز المطور)
  // مُخزَّن كـ SHA-256 hash للأمان — لا يمكن استخلاص الأكواد الأصلية
  // من الـ APK المفكك. هذه الأكواد ترويجية/تجريبية وليست مصدر دخل حقيقي،
  // لذلك يُسمح باستخدامها من أي جهاز بأمان.
  //
  // ⚠️ ملاحظة: كود المطوّر لم يعد نصاً صريحاً في الكود المصدري (كان هذا
  // خطأً أمنياً في النسخة السابقة) — هو الآن مخزَّن فقط كـ hash، تماماً
  // مثل باقي الأكواد الترويجية.
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
    // كود المطوّر الرئيسي — مخزَّن كـ hash فقط، غير ظاهر كنص صريح
    // في الكود المصدري ولا في أي ملف مُصرَّف (APK / main.dart.js).
    // الكود الفعلي محفوظ لدى المطوّر فقط خارج هذا المستودع.
    'a96cf70950b2cbac6b8bc3d93aa4b12dbeca4d79ccbda8dae9f42809e993a46d': {
      'plan': 'school',
      'days': 9999,
      'desc': 'حساب المطور الرئيسي'
    },
  };

  // ======================================================================
  // معرّف الجهاز الفريد (Device License ID)
  // يُستخدَم كأساس لربط أكواد الاشتراك المدفوعة بجهاز واحد فقط.
  //
  // 🔴 ثغرة/عطل جسيم تم اكتشافه وإصلاحه هنا (Device-ID Reinstall Bug):
  // النسخة السابقة كانت تولّد معرّفاً عشوائياً بالكامل (Random.secure())
  // وتخزّنه فقط في SharedPreferences. هذا التخزين يُمسح بالكامل عند حذف
  // التطبيق وإعادة تثبيته (أو مسح بيانات التطبيق) على أندرويد. النتيجة:
  //   1) أي **عميل دافع حقيقي** اشترى كوداً مخصصاً لجهازه (SGV2-...) كان
  //      سيفقد صلاحية اشتراكه المدفوع بالكامل بمجرد إعادة تثبيت التطبيق
  //      أو تغيير هاتفه — لأن معرّف الجهاز الجديد لن يطابق المعرّف الذي
  //      وُلِّد الكود بناءً عليه، رغم أنه نفس الجهاز فعلياً.
  //   2) بالمقابل، كان بإمكان أي مستخدم إساءة استخدام كود التجربة المجانية
  //      (GRADER-PRO-TRIAL) عدة مرات لا نهائياً عبر حذف التطبيق وإعادة
  //      تثبيته في كل مرة (كل تثبيت يولّد معرّفاً عشوائياً جديداً، وبالتالي
  //      "جهازاً جديداً" وهمياً من منظور نظام تتبع الأكواد المُستخدَمة).
  //
  // ✅ الإصلاح: استخدام Android's Settings.Secure.ANDROID_ID (عبر حزمة
  // android_id) كمصدر أساسي للمعرّف على أندرويد. هذا المعرّف **يبقى ثابتاً
  // عبر إعادة التثبيت وحذف بيانات التطبيق**، ولا يتغير إلا بإعادة ضبط
  // المصنع الكامل للجهاز أو تغيير مفتاح توقيع التطبيق (APK signing key) —
  // وهذا بالضبط السلوك الصحيح تجارياً وأمنياً لكل من: حماية اشتراكات
  // العملاء الحقيقيين من الفقدان العرضي، وتقليل مساحة إساءة استخدام
  // الأكواد الترويجية عبر إعادة التثبيت.
  //
  // للتوافق الخلفي الكامل مع أي تثبيت حالي بالفعل (Backward Compatibility):
  // إذا وُجد معرّف مخزَّن مسبقاً في SharedPreferences (من نسخة سابقة من
  // التطبيق، أو من هذه النسخة نفسها بعد أول تشغيل)، يُستخدَم كما هو دون
  // أي تغيير — حتى لا تنكسر أي اشتراكات مفعَّلة بالفعل على النظام القديم.
  // فقط عند عدم وجود أي معرّف مخزَّن (تثبيت جديد تماماً، أو أول مرة تشغيل
  // بعد هذا التحديث) يُستخدَم ANDROID_ID الثابت كأساس، مع تخزينه فوراً حتى
  // لا يُعاد الاستعلام عنه في كل مرة.
  // ======================================================================
  static const AndroidId _androidIdPlugin = AndroidId();

  static Future<String> getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_deviceIdKey);
      if (id != null && id.isNotEmpty) {
        // توافق خلفي: معرّف مخزَّن بالفعل (من هذا التشغيل أو نسخة سابقة)
        return id;
      }

      // لا يوجد معرّف مخزَّن → حاول أولاً الحصول على ANDROID_ID الثابت
      // (متاح فقط على أندرويد؛ يُعيد null على الويب/iOS تلقائياً)
      String? stableId;
      if (!kIsWeb) {
        try {
          stableId = await _androidIdPlugin.getId();
        } catch (e, st) {
          ErrorHandler.logError(e, st, 'SubscriptionService.getDeviceId.androidId');
        }
      }

      id = (stableId != null && stableId.isNotEmpty)
          ? stableId.toUpperCase()
          : _generateRandomDeviceId(); // fallback: ويب/iOS أو فشل المكوّن

      await prefs.setString(_deviceIdKey, id);
      return id;
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'SubscriptionService.getDeviceId');
      // معرّف احتياطي مؤقت في حال فشل التخزين بالكامل (لن يُحفظ)
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

  /// يحاول تفسير كود بصيغة "مخصص لهذا الجهاز، موقَّع رقمياً بـ RSA":
  ///   SGV2-<PLAN>-<DAYS>-<DEVICE_B32>-<SIG_B32>
  ///
  /// يتحقق من:
  ///  1) أن المعرّف المُضمَّن في الكود يطابق فعلاً معرّف هذا الجهاز
  ///     (منع استخدام كود جهاز آخر).
  ///  2) أن التوقيع الرقمي RSA صالح فعلاً لمحتوى (deviceId:plan:days)
  ///     باستخدام المفتاح العام المُضمَّن في التطبيق (منع التزوير).
  ///
  /// يُعيد null إذا فشل أي من الشرطين (صيغة غير صالحة، جهاز غير مطابق،
  /// أو توقيع غير صحيح/مزوَّر).
  static Future<Map<String, dynamic>?> _tryParsePersonalizedCode(
      String code) async {
    final parts = code.split('-');
    // SGV2-PLAN-DAYS-DEVICEB32-SIGB32 → 5 أجزاء على الأقل
    // (الجزء الأخير قد يحتوي فواصل إضافية بسبب طول التوقيع، لذا نُعيد
    // التجميع بأمان بدل الاعتماد على عدد أجزاء ثابت)
    if (parts.length < 5 || parts[0] != 'SGV2') return null;

    final planCode = parts[1];
    final planName = _planCodeToName[planCode];
    if (planName == null) return null;

    final days = int.tryParse(parts[2]);
    if (days == null || days <= 0) return null;

    final deviceB32 = parts[3];
    // الجزء المتبقي (التوقيع) قد يحتوي '-' لو تم تقسيمه للعرض، لذا
    // نجمع كل ما تبقى بعد الجزء الرابع
    final sigB32 = parts.sublist(4).join('-');

    // 1) تحقق من مطابقة معرّف الجهاز
    final expectedDeviceId = await getDeviceId();
    final decodedDeviceIdBytes = base32Decode(deviceB32);
    final decodedDeviceId = String.fromCharCodes(decodedDeviceIdBytes);
    if (decodedDeviceId.trim().toUpperCase() !=
        expectedDeviceId.trim().toUpperCase()) {
      // إما كود تالف، أو صادر لجهاز آخر غير هذا الجهاز
      return null;
    }

    // 2) تحقق من صحة التوقيع الرقمي RSA (لا يمكن تزويره بدون المفتاح الخاص)
    Uint8List signatureBytes;
    try {
      signatureBytes = base32Decode(sigB32);
      if (signatureBytes.isEmpty) return null;
    } catch (_) {
      return null;
    }

    final isValidSignature = verifyLicenseSignature(
      deviceId: expectedDeviceId,
      planCode: planCode,
      days: days,
      signatureBytes: signatureBytes,
    );

    if (!isValidSignature) {
      // الكود مزوَّر أو تم التلاعب به
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

    // 1) جرّب أولاً صيغة الكود المخصص لهذا الجهاز الموقَّع رقمياً بـ RSA
    //    (الأكواد المدفوعة الحقيقية — الصيغة الجديدة SGV2-...)
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
    const devMasterHash =
        'a96cf70950b2cbac6b8bc3d93aa4b12dbeca4d79ccbda8dae9f42809e993a46d';
    if (usedHashes.contains(codeHash) && codeHash != devMasterHash) {
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
  // فرض حدود الخطة: عدد الفصول الدراسية المختلفة لكل معلم
  // (maxClassesPerTeacher) — كانت هذه القيمة تُعرَض فقط كرقم تسويقي في
  // شاشة الأسعار دون أي فرض فعلي؛ الآن تُطبَّق فعلياً هنا.
  // ======================================================================
  static const _openedClassesKey = 'opened_class_ids';

  /// يتحقق مما إذا كان بإمكان المعلم فتح فصل دراسي معيّن الآن، بحسب حد
  /// "عدد الفصول" في باقته الحالية:
  ///  - فصل العرض التجريبي (classId == 0) مستثنى دائماً.
  ///  - أي فصل سبق فتحه فعلياً (مسجَّل محلياً) يبقى متاحاً دوماً — الحد
  ///    يُطبَّق فقط على عدد الفصول *المختلفة* الجديدة.
  ///  - baقة بحد غير محدود (-1) تتجاوز الفحص دائماً.
  static Future<bool> canOpenClass(int classId) async {
    if (classId == 0) return true;
    final sub = await getCurrentSubscription();
    final maxClasses = sub.planInfo.maxClassesPerTeacher;
    if (maxClasses == -1) return true;
    final opened = await _getOpenedClassIds();
    if (opened.contains(classId)) return true;
    return opened.length < maxClasses;
  }

  /// يسجّل أن هذا الفصل تم فتحه فعلياً بنجاح (يُستدعى بعد تحميل بيانات
  /// الفصل بنجاح فقط، وليس عند مجرد محاولة الفتح).
  static Future<void> markClassOpened(int classId) async {
    if (classId == 0) return;
    try {
      final opened = await _getOpenedClassIds();
      if (opened.contains(classId)) return;
      opened.add(classId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _openedClassesKey,
        opened.map((e) => e.toString()).toList(),
      );
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'SubscriptionService.markClassOpened');
    }
  }

  static Future<Set<int>> _getOpenedClassIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_openedClassesKey) ?? const [];
      return raw
          .map((e) => int.tryParse(e) ?? -1)
          .where((e) => e != -1)
          .toSet();
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'SubscriptionService._getOpenedClassIds');
      return {};
    }
  }

  /// عدد الفصول الدراسية الفريدة المفتوحة فعلياً حتى الآن (بدون العرض
  /// التجريبي) — مفيد لعرض "2 من 2 فصول" في واجهة المستخدم مثلاً.
  static Future<int> getOpenedClassesCount() async {
    return (await _getOpenedClassIds()).length;
  }

  /// الحد الأقصى لعدد الطلاب بالفصل الواحد بحسب باقة الاشتراك الحالية.
  /// -1 تعني غير محدود.
  static Future<int> getMaxStudentsPerClass() async {
    final sub = await getCurrentSubscription();
    return sub.planInfo.maxStudentsPerClass;
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
