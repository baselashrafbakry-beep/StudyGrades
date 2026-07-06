import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_id/android_id.dart';
import '../models/subscription_model.dart';
import '../utils/error_handler.dart';
import '../security/rsa_license_verifier.dart';
import 'api_client.dart';

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
  static const _lastSeenTimeKey = 'subscription_last_seen_epoch_ms';

  // ────────────────────────────────────────────────────────────────
  // نقطة حَقن للاختبار فقط (Testability Seam) — بنفس نمط
  // `GradingProvider.debugSyncOverride` المُستخدَم في بقية المشروع.
  // تبقى null دائماً في كود الإنتاج (فيُستخدَم `apiClient.
  // getSubscriptionStatus()` الحقيقي كما هو)، وتُستخدَم فقط في
  // `test/subscription_sync_with_server_test.dart` للتحكم الحتمي في
  // استجابة "السيرفر" دون أي اتصال شبكة فعلي أو حاجة لتشغيل Dio/
  // dio_adapter وهمي.
  // ────────────────────────────────────────────────────────────────
  @visibleForTesting
  static Future<Map<String, dynamic>?> Function()? debugServerFetchOverride;

  /// نقطة حَقن للاختبار فقط لـ `apiClient.redeemActivationCode()` — انظر
  /// التوثيق الكامل أعلى تلك الدالة في `api_client.dart` لفهم سياسة
  /// "تسجيل الاستخدام على السيرفر" التي صُمِّمت لمنع إعادة استخدام نفس
  /// كود الاشتراك (تجريبي أو مدفوع) عبر حذف التطبيق وإعادة تثبيته.
  @visibleForTesting
  static Future<bool?> Function({
    required String codeHash,
    required String deviceId,
  })? debugRedeemOverride;

  // ======================================================================
  // 🔴 تحصين ضد التلاعب بساعة الجهاز (Clock Manipulation) — ثغرة تجارية
  // جسيمة أخرى تم اكتشافها أثناء تدقيق Pillar 2:
  //
  // كل منطق انتهاء الاشتراك في هذا الملف (وفي `UserSubscription.isExpired`
  // / `isExpiringSoon` في subscription_model.dart) كان يعتمد حصرياً على
  // `DateTime.now()` الخام القادم من ساعة نظام التشغيل. على أندرويد، أي
  // مستخدم عادي (بدون أي صلاحيات جذر/root) يمكنه فتح "الإعدادات ← التاريخ
  // والوقت" وإرجاع ساعة الجهاز يدوياً إلى تاريخ في الماضي في كل مرة يقترب
  // فيها اشتراكه (تجريبي أو **مدفوع حقيقي عبر كود RSA**) من الانتهاء، ثم
  // إعادتها لاحقاً — وبذلك يبقى `expiryDate.isAfter(DateTime.now())` صحيحاً
  // إلى الأبد رغم انتهاء المدة الفعلية الحقيقية. هذا تسريب إيرادات مباشر
  // بنفس خطورة ثغرة "إعادة التثبيت" التي أُصلحت أعلاه، وأسهل تنفيذاً من
  // قِبل أي مستخدم عادي (لا يتطلب حذف التطبيق، فقط تغيير إعداد نظام).
  //
  // ✅ الإصلاح (Monotonic Time Ratchet — "مزلاج زمني أحادي الاتجاه"):
  // نخزّن محلياً (SharedPreferences) أكبر توقيت (epoch ms) شوهد فعلياً على
  // هذا الجهاز حتى الآن. كل مرة يُطلَب فيها "الوقت الحالي لأغراض ترخيص
  // الاشتراك" عبر `_licenseNow()`، نقارن `DateTime.now()` الفعلي بهذه
  // القيمة المخزَّنة ونُعيد **الأكبر بينهما**، ثم نُحدِّث التخزين فوراً إلى
  // هذه القيمة الجديدة. النتيجة: هذا "الوقت المُرخَّص" لا يمكن أن يتراجع
  // إلى الخلف أبداً بغضّ النظر عمّا تفعله ساعة النظام — فإرجاع الساعة للخلف
  // يجعل `DateTime.now()` أصغر من آخر قيمة محفوظة، فتُتجاهَل تلقائياً
  // ويُستخدَم آخر وقت "حقيقي" معروف بدلاً منه. تقديم الساعة للأمام (بلا أي
  // فائدة للمستخدم في هذا السياق) يُحدِّث المزلاج بأمان كالمعتاد.
  //
  // ملاحظة أمانة: هذا الحل **best-effort محلي بحت** (لا يعتمد على أي خادم
  // وقت خارجي)، وهو كافٍ تماماً لمنع سيناريو "إرجاع الساعة للخلف" الشائع
  // والسهل التنفيذ، لكنه لا يمنع نظرياً مستخدماً متقدماً جداً يُعيد أيضاً
  // ضبط التطبيق لحالة تثبيت جديدة تماماً (SharedPreferences فارغة) في نفس
  // اللحظة — وهذه الحالة الأخيرة مغطاة بشكل منفصل عبر "سجل الاستخدام على
  // السيرفر" (`redeemActivationCode`) أعلاه لأي كود مدفوع فعلياً، طالما
  // الجهاز متصل بالإنترنت ولو لمرة واحدة بعد إعادة التثبيت.
  // ======================================================================

  /// نقطة حَقن للاختبار فقط: تسمح بتثبيت "ساعة نظام" وهمية بدل
  /// `DateTime.now()` الحقيقية، للتحقق الحتمي من سلوك المزلاج الزمني دون
  /// انتظار زمن حقيقي أو التلاعب بساعة نظام التشغيل الفعلية أثناء الاختبار.
  @visibleForTesting
  static DateTime Function()? debugClockOverride;

  static DateTime _systemNow() =>
      debugClockOverride != null ? debugClockOverride!() : DateTime.now();

  /// يُعيد "الوقت المُرخَّص" الآمن ضد التلاعب — انظر التوثيق أعلى. هذه هي
  /// الدالة الوحيدة التي يجب استخدامها في هذا الملف لأي مقارنة تتعلق
  /// بانتهاء/بدء اشتراك (بدلاً من `DateTime.now()` مباشرة).
  static Future<DateTime> _licenseNow() async {
    final real = _systemNow();
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(_lastSeenTimeKey);
      final last =
          (lastMs != null) ? DateTime.fromMillisecondsSinceEpoch(lastMs) : null;
      final safe = (last != null && last.isAfter(real)) ? last : real;
      // نُحدِّث المزلاج فقط لو تقدَّم فعلياً (لا داعي لكتابة غير ضرورية)
      if (last == null || safe.isAfter(last)) {
        await prefs.setInt(_lastSeenTimeKey, safe.millisecondsSinceEpoch);
      }
      return safe;
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'SubscriptionService._licenseNow');
      return real; // فشل القراءة/الكتابة → أقل سوءاً هو استخدام الوقت الفعلي
    }
  }

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
    // STUDY2026-TRIAL → تجربة ستارتر شهر
    _hashCode('STUDY2026-TRIAL'): {
      'plan': 'basic',
      'days': 30,
      'desc': 'تجربة ستارتر شهر'
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
          ErrorHandler.logError(
              e, st, 'SubscriptionService.getDeviceId.androidId');
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

  // ⚠️ محدَّث ليطابق الأسماء التجارية الرسمية من StudyGrades-commercial.env
  // (basic=Starter/ستارتر، pro=Professional/احترافي) — راجع التوثيق الكامل
  // أعلى SubscriptionPlans في subscription_model.dart.
  static const Map<String, String> _planLabelAr = {
    'basic': 'ستارتر',
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

    // 🔴 تحصين إضافي (best-effort) ضد إعادة استخدام الكود عبر حذف/إعادة
    // تثبيت التطبيق — انظر التوثيق الكامل أعلى
    // `ApiClient.redeemActivationCode()`. الفحص المحلي أعلاه (usedHashes)
    // وحده لا يكفي لأنه يُمسَح بالكامل عند إعادة التثبيت، بينما معرّف
    // الجهاز (deviceId) يبقى ثابتاً. هنا نسأل السيرفر (إن كان متصلاً)
    // "هل هذا الكود مُسجَّل بالفعل لجهاز *آخر* مختلف؟" — ونمنع التفعيل
    // فقط في حال تأكيد صريح وقاطع بذلك. لا يُشترَط اتصال ناجح للاستمرار
    // (Graceful Degradation): لو تعذّر الوصول للسيرفر (null) نُكمل
    // بالاعتماد على الفحص المحلي وحده — تماماً كسلوك النظام قبل هذا
    // الإصلاح — حتى لا تُفقَد قدرة التفعيل الأوفلاين الحقيقية.
    if (codeHash != devMasterHash) {
      final deviceId = await getDeviceId();
      final serverVerdict = debugRedeemOverride != null
          ? await debugRedeemOverride!(codeHash: codeHash, deviceId: deviceId)
          : await apiClient.redeemActivationCode(
              codeHash: codeHash, deviceId: deviceId);
      if (serverVerdict == false) {
        return ActivationResult.fail('هذا الرمز مُسجَّل بالفعل على جهاز آخر\n'
            'لا يمكن استخدام نفس الرمز على أكثر من جهاز\n'
            'تواصل مع المطور للحصول على رمز جديد إذا لزم الأمر');
      }
      // serverVerdict == true (مسموح) أو null (تعذّر الوصول للسيرفر) →
      // نُكمل التفعيل اعتماداً على الفحص المحلي فقط، بأمان تام.
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
    // ⚠️ نستخدم `_licenseNow()` (المزلاج الزمني الآمن) بدل `DateTime.now()`
    // الخام هنا أيضاً — انظر التوثيق الكامل أعلى هذا الملف — لضمان أن نقطة
    // بداية أي اشتراك جديد/مُمدَّد لا تعتمد أبداً على ساعة نظام قابلة
    // للتلاعب، وليتم "تسجيل" هذه اللحظة فوراً في المزلاج (Ratchet Anchor).
    final current = await getCurrentSubscription();
    final now = await _licenseNow();
    DateTime startDate = now;
    if (current.isActive &&
        current.isPaid &&
        current.expiryDate != null &&
        !(await _isExpiredSafe(current))) {
      // تمديد من نهاية الاشتراك الحالي
      startDate = current.expiryDate!;
    }
    final expiryDate = days == 9999
        ? DateTime(2099, 12, 31) // حساب المطور — لا ينتهي
        : startDate.add(Duration(days: days));

    final subscription = UserSubscription(
      plan: plan,
      startDate: now,
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
          // ⚠️ نستخدم `_isExpiredSafe()` (المزلاج الزمني) بدل `sub.isExpired`
          // الخام هنا — انظر التوثيق الكامل أعلى هذا الملف — لمنع تمديد
          // اشتراك منتهٍ فعلياً إلى ما لا نهاية عبر إرجاع ساعة الجهاز للخلف.
          if (!(await _isExpiredSafe(sub))) return await _withSafeDays(sub);
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
        if (!(await _isExpiredSafe(sub))) return await _withSafeDays(sub);
      }
    } catch (e, st) {
      ErrorHandler.logError(
          e, st, 'SubscriptionService.getCurrentSubscription');
    }
    return UserSubscription.free();
  }

  /// نسخة آمنة (ضد التلاعب بالساعة) من `UserSubscription.isExpired` —
  /// تستخدم `_licenseNow()` (المزلاج الزمني الأحادي الاتجاه) بدل
  /// `DateTime.now()` الخام المُستخدَم داخل الـ getter الأصلي في النموذج.
  static Future<bool> _isExpiredSafe(UserSubscription sub) async {
    if (sub.expiryDate == null) return false;
    final now = await _licenseNow();
    return now.isAfter(sub.expiryDate!);
  }

  /// يُعيد نسخة من الاشتراك بحقل `daysRemaining` مُعاد حسابه بأمان بناءً
  /// على `_licenseNow()` بدل الاعتماد على القيمة المخزَّنة وقت آخر حفظ
  /// (والتي كانت تُحسَب أصلاً عبر `DateTime.now()` الخام في
  /// `UserSubscription.fromJson`). هذا يضمن أن "الأيام المتبقية" المعروضة
  /// للمستخدم في الواجهة (`activate_subscription_screen.dart`) تتناقص
  /// بشكل صحيح مع مرور الوقت الحقيقي فقط، ولا تتجمَّد أو تُعاد للخلف لو
  /// تم إرجاع ساعة الجهاز.
  static Future<UserSubscription> _withSafeDays(UserSubscription sub) async {
    if (sub.expiryDate == null) return sub;
    final now = await _licenseNow();
    final safeDays = sub.expiryDate!.difference(now).inDays.clamp(0, 9999);
    if (safeDays == sub.daysRemaining) return sub;
    return UserSubscription(
      plan: sub.plan,
      startDate: sub.startDate,
      expiryDate: sub.expiryDate,
      isActive: sub.isActive,
      isTrial: sub.isTrial,
      daysRemaining: safeDays,
    );
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
  // 🔴 فرض حد "عدد المعلمين" (Seat Limits) — ثغرة تجارية جسيمة تم
  // اكتشافها أثناء تدقيق Pillar 2:
  //
  // كان الحقل `maxTeachers` موجوداً في `SubscriptionPlanInfo` ومعروضاً
  // فعلياً في شاشة الأسعار (subscription_screen.dart) كرقم تسويقي
  // ("1 معلم" / "غير محدود")، لكنه لم يكن يُفرَض في أي مكان فعلياً —
  // `AdminService.createUser()` كانت تسمح بإنشاء عدد غير محدود من
  // حسابات المعلمين بغضّ النظر عن باقة الاشتراك الحالية (حتى في الخطة
  // المجانية أو الأساسية أو الاحترافية التي تنص جميعها على "معلم واحد
  // فقط"). هذا يعني عملياً أن أي مدرسة كان بإمكانها استخدام باقة فردية
  // رخيصة (أو حتى المجانية) وإنشاء عدد غير محدود من حسابات المعلمين
  // تحتها دون أي قيد — وهي بالضبط الحالة التي من المفترض أن تدفع
  // مقابلها باقة "مدرسة" (school) ذات الحد غير المحدود (-1).
  //
  // ✅ الإصلاح: توفير `getMaxTeachers()` هنا (بنفس نمط
  // `getMaxStudentsPerClass()`)، واستدعاؤها إلزامياً من
  // `AdminService.createUser()` قبل السماح بإنشاء أي حساب جديد بدور
  // "معلم" — يُحسَب عدد حسابات المعلمين النشطة حالياً (باستثناء
  // المطوّر/المدير/المشرف الذين لا يُحتسَبون كـ "مقاعد معلمين")، ويُرفض
  // إنشاء حساب جديد إذا كان العدد الحالي يساوي أو يتجاوز حد الباقة.
  // ======================================================================

  /// الحد الأقصى لعدد حسابات "المعلمين" (Seats) المسموح بها بحسب باقة
  /// الاشتراك الحالية. -1 تعني غير محدود (خطة "مدرسة").
  static Future<int> getMaxTeachers() async {
    final sub = await getCurrentSubscription();
    return sub.planInfo.maxTeachers;
  }

  // ======================================================================
  // 🆕 حد "عدد الأجهزة" (Device Limit) — بحسب ملف الإعداد التجاري الرسمي
  // (STARTER_DEVICE_LIMIT=1 / PROFESSIONAL_DEVICE_LIMIT=2). راجع التوثيق
  // الكامل والصادق حول حدود الإنفاذ الفعلي أعلى حقل
  // `SubscriptionPlanInfo.maxDevices` في subscription_model.dart —
  // باختصار: النظام الحالي offline بالكامل ويربط كل كود ترخيص RSA بجهاز
  // واحد عند توليده، لذا خطة Starter (حد=1) محقَّقة ببنية النظام تلقائياً؛
  // خطة Professional (حد=2) تُدار حالياً عبر توليد كودين منفصلين عند
  // الطلب من المطوّر، وليس عبر فحص برمجي مركزي داخل هذا التطبيق (يتطلب
  // ذلك بنية حسابات على الباك-إند غير موجودة بعد في هذا المستودع).
  // ======================================================================

  /// الحد الأقصى لعدد الأجهزة المسموح تفعيل هذا الاشتراك عليها بحسب باقة
  /// الاشتراك الحالية. -1 تعني غير محدود.
  static Future<int> getMaxDevices() async {
    final sub = await getCurrentSubscription();
    return sub.planInfo.maxDevices;
  }

  // ======================================================================
  // 🔴 معمارية استقبال تحديثات بوابة الدفع (Paymob) — ثغرة معمارية
  // جسيمة تم اكتشافها أثناء تدقيق Pillar 2:
  //
  // النظام الحالي بالكامل محلي/offline: التفعيل يتم فقط عبر إدخال كود
  // موقَّع رقمياً (RSA) يدوياً من قِبل المستخدم. لا يوجد أي مسار برمجي
  // في التطبيق يتحقق من حالة اشتراك "من السيرفر" على الإطلاق. هذا يعني:
  //
  //  1) عند إضافة الدفع الإلكتروني عبر Paymob مستقبلاً، الـ Webhook الذي
  //     ترسله Paymob عند نجاح الدفع سيصل حصرياً إلى الباك-إند (Django
  //     على studygrades2026.pythonanywhere.com)، وليس للتطبيق نفسه —
  //     الـ webhooks هي أحداث خادم-لخادم (Server-to-Server) بطبيعتها
  //     ولا يمكن لأي تطبيق موبايل استقبالها مباشرة.
  //  2) بدون مسار مصالحة (Reconciliation) بين حالة الاشتراك "الرسمية"
  //     على السيرفر (التي يحدّثها الـ Webhook فور الدفع) وحالة الاشتراك
  //     "المحلية" في التطبيق (Hive/SharedPreferences)، سيدفع العميل فعلياً
  //     عبر Paymob لكن تطبيقه لن "يعرف" بذلك أبداً — لأن لا شيء يخبره.
  //
  // ✅ الحل المعماري المُطبَّق هنا: نمط "Pull-based Reconciliation".
  // بما أن التطبيق (العميل) لا يمكنه استقبال Webhook مباشرة، فهو بدلاً
  // من ذلك *يسأل* السيرفر دورياً عن آخر حالة اشتراك "رسمية" معروفة له
  // (GET /subscription/status/ — انظر ApiClient.getSubscriptionStatus)،
  // ويُحدِّث نسخته المحلية إذا كانت حالة السيرفر أحدث/مختلفة. تدفق العمل
  // الكامل المتوقَّع من الباك-إند (خارج نطاق هذا المستودع، لكن موثَّق هنا
  // ليعرفه أي مطوّر باك-إند يُكمل هذا التكامل):
  //
  //   Paymob (نجاح الدفع)
  //        │  HTTPS POST (Webhook/Callback موقَّع بـ HMAC من Paymob)
  //        ▼
  //   Django Backend: /api/mobile/payments/paymob/webhook/
  //        │  يتحقق من توقيع HMAC الخاص بـ Paymob (hmac Secret الخاص
  //        │  بالتاجر)، ثم يُحدِّث سجل اشتراك المعلم/المدرسة في قاعدة
  //        │  بيانات السيرفر (plan/expiry_date/is_active)
  //        ▼
  //   التطبيق (لاحقاً، عند فتحه أو دورياً): GET /subscription/status/
  //        │  يُعيد نفس السجل المُحدَّث فوراً
  //        ▼
  //   SubscriptionService.syncWithServer() ← هذه الدالة
  //        │  تُقارن مع الحالة المحلية وتُحدِّثها إذا لزم الأمر
  //        ▼
  //   Hive/SharedPreferences محلياً (نفس مسار _saveSubscription الحالي)
  //
  // هذا النمط لا يتطلب أي بنية تحتية إضافية (لا Push Notifications ولا
  // WebSockets)، يعمل بشكل موثوق حتى مع اتصال متقطع (best-effort، لا
  // يفشل التطبيق أبداً إذا تعذّر الوصول للسيرفر)، ويحل بالضبط نفس مشكلة
  // "الدفع نجح لكن التطبيق لا يعرف" التي تنشأ حتماً مع أي بوابة دفع تعمل
  // عبر Webhooks خادم-لخادم.
  //
  // ⚠️ سياسة الدمج (Merge Policy) المُتَّبعة أدناه: حالة السيرفر تُعتمَد
  // فقط إذا كانت اشتراكاً "مدفوعاً حقيقياً" (isPaid) لتفادي أن يُصفِّر
  // خطأً في السيرفر (مثلاً حساب تجريبي جديد لم يُفعَّل بعد) اشتراكاً
  // محلياً مدفوعاً فعلياً عبر كود RSA يدوي. بعبارة أخرى: تحديثات
  // السيرفر تُستخدَم لـ *ترقية*/تحديث الاشتراك، وليس لإسقاطه محلياً إلى
  // "مجاني" ما لم يكن السيرفر صريحاً بأن الاشتراك انتهى فعلياً
  // (is_active == false مع وجود plan مدفوعة سابقاً — حالة "تم الإلغاء
  // أو انتهت صلاحية الدفع المتكرر").
  // ======================================================================

  /// يُصالِح (Reconciles) حالة الاشتراك المحلية مع حالة "رسمية" من
  /// السيرفر (التي قد تكون تحدَّثت فوراً عبر Webhook من بوابة الدفع
  /// Paymob دون أي تدخل من المستخدم داخل التطبيق نفسه).
  ///
  /// آمن تماماً للاستدعاء بشكل متكرر (عند بدء التطبيق، عند فتح شاشة
  /// الاشتراك، أو دورياً في الخلفية) — best-effort بالكامل: أي فشل في
  /// الشبكة أو صيغة غير متوقعة من السيرفر يُسجَّل فقط عبر ErrorHandler
  /// ولا يُعدِّل أي شيء محلياً ولا يرمي أي استثناء للمستدعي.
  ///
  /// يُعيد `true` إذا تم فعلاً تحديث الاشتراك المحلي نتيجة هذه المزامنة
  /// (مفيد لعرض إشعار للمستخدم مثل "تم تفعيل اشتراكك! 🎉")، و`false` في
  /// أي حالة أخرى (لا تغيير / تعذّر الاتصال / حالة السيرفر غير صالحة).
  static Future<bool> syncWithServer() async {
    try {
      final serverData = debugServerFetchOverride != null
          ? await debugServerFetchOverride!()
          : await apiClient.getSubscriptionStatus();
      if (serverData == null) return false;

      final planName = serverData['plan']?.toString();
      if (planName == null) return false;
      final plan = SubscriptionPlan.values.firstWhere(
        (p) => p.name == planName,
        orElse: () => SubscriptionPlan.free,
      );

      final serverIsActive = serverData['is_active'] == true;
      final serverExpiry = serverData['expiry_date'] != null
          ? DateTime.tryParse(serverData['expiry_date'].toString())
          : null;
      final serverStart = serverData['start_date'] != null
          ? DateTime.tryParse(serverData['start_date'].toString())
          : null;
      final serverIsTrial = serverData['is_trial'] == true;

      // ⚠️ نستخدم `_licenseNow()` هنا أيضاً بدل `DateTime.now()` الخام،
      // للاتساق مع باقي الملف (انظر التوثيق الكامل أعلى قسم "المزلاج
      // الزمني"). صحيح أن حالة السيرفر هنا "رسمية" أصلاً ولا تعتمد على
      // ساعة هذا الجهاز لتحديد الانتهاء، لكن `daysRemaining` نفسها تُعرَض
      // لاحقاً في واجهة المستخدم، فيجب أن تبقى متسقة مع نفس "الوقت الآمن"
      // المُستخدَم في كل مكان آخر بالتطبيق (وإلا قد تظهر قيمتان مختلفتان
      // لعدد الأيام المتبقية بحسب المصدر الذي جلب منه الاشتراك).
      final now = await _licenseNow();
      final serverSub = UserSubscription(
        plan: plan,
        startDate: serverStart,
        expiryDate: serverExpiry,
        isActive: serverIsActive,
        isTrial: serverIsTrial,
        daysRemaining: serverExpiry != null
            ? serverExpiry.difference(now).inDays.clamp(0, 9999)
            : -1,
      );

      final localSub = await getCurrentSubscription();

      // سياسة الدمج: نطبّق تحديث السيرفر فقط في إحدى حالتين آمنتين:
      //  أ) السيرفر يُعلن عن خطة مدفوعة نشطة أحدث/مختلفة عن المحلية
      //     (ترقية اشتراك فورية عبر الدفع الإلكتروني).
      //  ب) السيرفر يُعلن صراحة أن خطة مدفوعة سابقاً لم تعد نشطة
      //     (is_active == false) — أي إلغاء/انتهاء دفع متكرر رسمي.
      final shouldApplyUpgrade = serverSub.isPaid &&
          serverIsActive &&
          (serverSub.plan != localSub.plan ||
              serverSub.expiryDate != localSub.expiryDate);

      final shouldApplyDeactivation =
          localSub.isPaid && !serverIsActive && planName == localSub.plan.name;

      if (shouldApplyUpgrade || shouldApplyDeactivation) {
        await _saveSubscription(serverSub);
        return true;
      }
      return false;
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'SubscriptionService.syncWithServer');
      return false;
    }
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
