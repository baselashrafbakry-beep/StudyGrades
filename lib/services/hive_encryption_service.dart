import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, debugPrint, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/error_handler.dart';

/// ════════════════════════════════════════════════════════════════════
/// 🔐 تشفير قاعدة البيانات المحلية (Hive) — AES-256 عبر HiveAesCipher
/// ════════════════════════════════════════════════════════════════════
/// هذا القرار الأمني موثَّق بالكامل هنا لأنه مفصلي وغير بديهي:
///
/// 1) لماذا Android/iOS فقط، وليس Web؟
///    على المنصات الأصلية، يُخزَّن Hive كملفات `.hive`/`.lock` على نظام
///    الملفات المحلي للجهاز — ملفات يمكن استخراجها فعلياً عبر: نسخة
///    احتياطية لجهاز مكسور الحماية (rooted/jailbroken)، أدوات ADB على
///    جهاز بوضع تصحيح مفعّل، أو الوصول الفعلي لجهاز مفقود/مسروق. تشفير
///    AES-256 هنا يوفّر حماية حقيقية وملموسة لبيانات الطلاب والدرجات.
///
///    على الويب، يُخزَّن Hive داخل IndexedDB الخاص بالمتصفح، وهو محمي
///    أصلاً (Sandboxed) على مستوى الأصل (Origin) بواسطة نموذج أمان
///    المتصفح نفسه. تشفير AES هناك يتطلب تخزين مفتاح دائم وموثوق بنفس
///    درجة الثقة كما على الموبايل — وهو غير مضمون على الويب (راجع
///    `_SafeStorage` في api_client.dart التي تتعمّد استخدام ذاكرة مؤقتة
///    فقط للويب). فقدان المفتاح يعني فقدان كل البيانات المحلية نهائياً.
///    القرار: **لا تشفير Hive على الويب — نعتمد على عزل IndexedDB
///    بالمتصفح كحد أمان كافٍ لهذه المنصة تحديداً.**
///
/// 2) كيف يُخزَّن مفتاح AES (32 بايت/256-بت) على Android/iOS؟
///    عبر `FlutterSecureStorage` — نفس النمط المستخدم في `_SafeStorage`
///    داخل `api_client.dart`. يُولَّد المفتاح عشوائياً (`Random.secure()`)
///    مرة واحدة فقط عند أول تشغيل، ثم يُعاد استخدامه في كل تشغيل لاحق.
///
/// 3) الترحيل الآمن للبيانات القديمة غير المشفَّرة (Migration) —
///    **بدون أي خطر تلف بيانات**:
///    محاولة فتح صندوق Hive قديم غير مشفَّر مباشرةً بـ `encryptionCipher`
///    جديد **ليست آمنة كما قد يبدو للوهلة الأولى**: افتراضياً
///    (`crashRecovery: true`)، تعتبر Hive أي بيانات تفشل التحقق من CRC
///    (كل البيانات القديمة ستفشل، لأنها لم تُشفَّر بهذا المفتاح أصلاً)
///    "تلفاً" (corruption) وتقوم تلقائياً و**بشكل مدمِّر** بـ"استعادة"
///    الملف عبر قطعه (`truncate`) عند أول نقطة فشل — وبما أن أول إطار
///    (frame) سيفشل حتماً، فهذا يعني تصفير الملف بالكامل، أي **حذف كل
///    البيانات القديمة فوراً دون أي استثناء يُمكن اصطياده والتراجع عنه**.
///
///    لذلك يتّبع [openEncryptedBox] تسلسلاً آمناً مختلفاً تماماً:
///      أ) إن كان الصندوق معروفاً مسبقاً بأنه مُرحَّل ومشفَّر بالفعل
///         (محفوظ في SharedPreferences من عملية ترحيل سابقة ناجحة) →
///         يُفتَح مباشرة بالـ cipher (المسار الطبيعي لكل تشغيل بعد أول
///         ترحيل، بلا أي عبء إضافي).
///      ب) وإلا: تُجرى محاولة فتح **تشخيصية آمنة تماماً** بلا أي cipher
///         ومع `crashRecovery: false` صراحةً — هذا يمنع أي استعادة
///         مدمِّرة؛ الفشل هنا (إن حدث، لأن الصندوق مشفَّر بالفعل من قبل)
///         هو مجرد استثناء "نظيف" لا يُغيّر أي بايت على القرص إطلاقاً.
///         - نجاح الفتح التشخيصي يعني: إما صندوق جديد تماماً (لا بيانات)
///           أو صندوق قديم يحوي بيانات حقيقية غير مشفَّرة. في الحالتين
///           تُقرَأ كل البيانات إلى الذاكرة، يُغلَق الصندوق، يُحذَف من
///           القرص (فقط بعد نجاح القراءة الكاملة)، ثم يُعاد فتحه مشفَّراً
///           وتُكتب البيانات القديمة فيه من جديد (تُشفَّر تلقائياً).
///         - فشل الفتح التشخيصي يعني على الأرجح أن الصندوق مشفَّر بالفعل
///           (بايتات عشوائية تفشل فحص CRC كنص عادي) → يُفتَح مباشرة
///           بالـ cipher الصحيح.
///      ج) في الحالتين، بمجرد نجاح الفتح بالـ cipher، يُسجَّل اسم
///         الصندوق في SharedPreferences كـ"مُرحَّل" لتفادي إعادة محاولة
///         الفتح التشخيصي في كل تشغيل لاحق (تحسين للأداء، غير حرِج
///         للأمان — إن فُقد هذا السجل لأي سبب ستُعاد المحاولة التشخيصية
///         بأمان تام دون أي خطر لأنها غير مدمِّرة أصلاً).
class HiveEncryptionService {
  HiveEncryptionService._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _keyStorageKey = 'hive_aes256_master_key_v1';
  static const String _migratedBoxesPrefKey = 'hive_encrypted_boxes_v1';

  static HiveCipher? _cachedCipher;
  static bool _resolved = false;
  static Set<String>? _migratedBoxesCache;

  /// ⚠️ للاختبارات فقط — يُصفِّر كل الحالة المخبَّأة داخلياً لمحاكاة
  /// "إعادة تشغيل التطبيق" ضمن نفس عملية الاختبار (نفس Dart VM run).
  /// لا يُستدعى إطلاقاً من كود الإنتاج.
  @visibleForTesting
  static void resetCacheForTesting() {
    _cachedCipher = null;
    _resolved = false;
    _migratedBoxesCache = null;
  }

  /// يُرجع الـ cipher المستخدَم لتشفير كل صناديق Hive على Android/iOS،
  /// أو `null` على الويب أو عند فشل التخزين الآمن (Fail-safe: التطبيق
  /// يستمر بالعمل بلا تشفير مؤقتاً بدلاً من رفض العمل أوفلاين بالكامل).
  static Future<HiveCipher?> getCipher() async {
    if (kIsWeb) return null;
    if (_resolved) return _cachedCipher;
    _resolved = true;
    try {
      final keyBytes = await _getOrCreateKey();
      _cachedCipher = HiveAesCipher(keyBytes);
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'HiveEncryptionService.getCipher');
      _cachedCipher = null;
    }
    return _cachedCipher;
  }

  static Future<List<int>> _getOrCreateKey() async {
    final existing = await _secureStorage.read(key: _keyStorageKey);
    if (existing != null && existing.isNotEmpty) {
      final decoded = base64Decode(existing);
      if (decoded.length == 32) return decoded;
      ErrorHandler.logError(
        ArgumentError('Invalid stored Hive key length: ${decoded.length}'),
        StackTrace.current,
        'HiveEncryptionService._getOrCreateKey.invalidLength',
      );
    }
    final rand = Random.secure();
    final keyBytes =
        Uint8List.fromList(List<int>.generate(32, (_) => rand.nextInt(256)));
    await _secureStorage.write(
      key: _keyStorageKey,
      value: base64Encode(keyBytes),
    );
    return keyBytes;
  }

  static Future<Set<String>> _getMigratedBoxes() async {
    if (_migratedBoxesCache != null) return _migratedBoxesCache!;
    try {
      final prefs = await SharedPreferences.getInstance();
      _migratedBoxesCache =
          (prefs.getStringList(_migratedBoxesPrefKey) ?? []).toSet();
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'HiveEncryptionService._getMigratedBoxes');
      _migratedBoxesCache = {};
    }
    return _migratedBoxesCache!;
  }

  static Future<void> _markBoxMigrated(String name) async {
    try {
      final set = await _getMigratedBoxes();
      set.add(name);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_migratedBoxesPrefKey, set.toList());
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'HiveEncryptionService._markBoxMigrated');
      // فشل التسجيل هنا غير حرِج — يعني فقط إعادة محاولة الفتح
      // التشخيصي الآمن (غير المدمِّر) في المرة القادمة، لا أكثر.
    }
  }

  /// يفتح صندوق Hive بأمان مع تشفير AES-256 (على Android/iOS) وترحيل
  /// تلقائي وشفاف لأي بيانات قديمة غير مشفَّرة من إصدار سابق للتطبيق —
  /// دون أي خطر فقدان بيانات (راجع توثيق الكلاس أعلاه للتفاصيل الكاملة).
  /// آمن للاستدعاء المتكرر لنفس الاسم بفضل فحص `Hive.isBoxOpen()`.
  static Future<Box> openEncryptedBox(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box(name);

    final cipher = await getCipher();
    if (cipher == null) {
      // الويب، أو فشل التخزين الآمن → فتح عادي بلا تشفير (بلا أي تغيير
      // عن سلوك التطبيق قبل هذا التحديث في هذه الحالة تحديداً).
      return Hive.openBox(name);
    }

    final migrated = await _getMigratedBoxes();
    if (migrated.contains(name)) {
      // المسار الطبيعي لكل تشغيل بعد أول ترحيل ناجح — فتح مباشر مشفَّر.
      return Hive.openBox(name, encryptionCipher: cipher);
    }

    // فتح تشخيصي آمن تماماً (crashRecovery: false يمنع أي استعادة
    // مدمِّرة للملف عند فشل التحقق من CRC — راجع التوثيق أعلاه).
    Map<dynamic, dynamic>? plainData;
    try {
      final plainBox = await Hive.openBox(name, crashRecovery: false);
      plainData = Map.of(plainBox.toMap());
      await plainBox.close();
    } catch (e) {
      // الفتح التشخيصي فشل — الصندوق على الأرجح مشفَّر بالفعل (بايتات
      // عشوائية تفشل فحص CRC كنص عادي)، وهذا لا يُغيّر أي بايت على
      // القرص إطلاقاً بفضل crashRecovery:false. لا حاجة لأي إجراء إضافي.
      if (kDebugMode) {
        debugPrint(
          '[HiveEncryption] "$name": الفتح التشخيصي فشل ($e) — '
          'يبدو مشفَّراً بالفعل، سيُفتح مباشرة بالمفتاح.',
        );
      }
    }

    try {
      if (plainData != null) {
        // نجح الفتح التشخيصي: إما صندوق جديد فارغ، أو صندوق قديم يحوي
        // بيانات فعلية غير مشفَّرة. في الحالتين: نحذف الملف الحالي من
        // القرص (فقط بعد نجاح قراءة كل بياناته بالكامل أعلاه)، ثم نعيد
        // فتحه مشفَّراً، ثم نكتب أي بيانات قديمة فيه من جديد.
        await Hive.deleteBoxFromDisk(name);
        final encBox = await Hive.openBox(name, encryptionCipher: cipher);
        if (plainData.isNotEmpty) {
          await encBox.putAll(plainData);
          if (kDebugMode) {
            debugPrint(
              '[HiveEncryption] ✅ تم ترحيل ${plainData.length} عنصر من '
              '"$name" إلى صندوق مشفَّر (AES-256) بنجاح دون أي فقدان بيانات',
            );
          }
        }
        await _markBoxMigrated(name);
        return encBox;
      } else {
        // الصندوق مشفَّر بالفعل من ترحيل سابق (لكن لم يُسجَّل في
        // SharedPreferences لأي سبب — مثلاً بعد استعادة نسخة احتياطية) —
        // نفتحه مباشرة بالـ cipher الصحيح ونسجّله الآن.
        final encBox = await Hive.openBox(name, encryptionCipher: cipher);
        await _markBoxMigrated(name);
        return encBox;
      }
    } catch (e, st) {
      ErrorHandler.logError(
        e,
        st,
        'HiveEncryptionService.openEncryptedBox[$name].finalOpen',
      );
      rethrow;
    }
  }
}
