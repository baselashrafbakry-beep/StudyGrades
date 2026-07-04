import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import '../models/hierarchy_model.dart';
import '../models/student_model.dart';
import '../utils/error_handler.dart';

/// --------------------------------------------------------------------------
/// طبقة تخزين آمنة — تتعامل مع Web بأمان دون WASM warnings
/// على Web: يُستخدم ذاكرة مؤقتة داخل الجلسة (session memory)
/// على Mobile: يُستخدم FlutterSecureStorage المشفّر
/// --------------------------------------------------------------------------
class _SafeStorage {
  static const FlutterSecureStorage _native = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// ذاكرة مؤقتة للويب (تُمسح عند إغلاق التبويب — مناسب للحماية)
  static final Map<String, String> _webMemory = {};

  static Future<String?> read({required String key}) async {
    if (kIsWeb) return _webMemory[key];
    try {
      return await _native.read(key: key);
    } catch (e, st) {
      ErrorHandler.logError(e, st, '_SafeStorage.read[$key]');
      return null;
    }
  }

  static Future<void> write({
    required String key,
    required String value,
  }) async {
    if (kIsWeb) {
      _webMemory[key] = value;
      return;
    }
    try {
      await _native.write(key: key, value: value);
    } catch (e, st) {
      ErrorHandler.logError(e, st, '_SafeStorage.write[$key]');
    }
  }

  static Future<void> delete({required String key}) async {
    if (kIsWeb) {
      _webMemory.remove(key);
      return;
    }
    try {
      await _native.delete(key: key);
    } catch (e, st) {
      ErrorHandler.logError(e, st, '_SafeStorage.delete[$key]');
    }
  }

  // ignore: unused_element
  static Future<void> _deleteAll() async {
    if (kIsWeb) {
      _webMemory.clear();
      return;
    }
    try {
      await _native.deleteAll();
    } catch (e, st) {
      ErrorHandler.logError(e, st, '_SafeStorage.deleteAll');
    }
  }
}

/// --------------------------------------------------------------------------
/// API Client — يتصل بـ Django REST backend عبر JWT + auto-refresh + retry
/// --------------------------------------------------------------------------
class ApiClient {
  /// Base URL — قابل للتخصيص عند البناء عبر `--dart-define=API_BASE_URL=...`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://studygrades2026.pythonanywhere.com/api/mobile',
  );

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _userKey = 'cached_user';

  late final Dio _dio;
  Future<String?>? _refreshFuture;

  /// Dio مستقل ومُعاد استخدامه لطلب تجديد التوكن تحديداً (بدل إنشاء
  /// `Dio()` جديد في كل استدعاء لـ `_refreshAccessToken()` — تحسين أداء
  /// بسيط بالإضافة إلى جعله قابلاً للحقن في الاختبارات، انظر
  /// `debugSetHttpClientAdapter` أدناه).
  late final Dio _refreshDio = Dio();

  /// نقطة حَقن للاختبار فقط — تسمح باستبدال الـ HttpClientAdapter الحقيقي
  /// (الذي يُجري اتصال شبكة فعلياً) بمحاكٍ (fake) حتمي داخل `flutter test`،
  /// لاختبار سيناريوهات دقيقة (رفض 401/403 نهائي مقابل انقطاع شبكة مؤقت
  /// أثناء تجديد التوكن) دون أي اتصال حقيقي بخادم الإنتاج. لا تأثير على
  /// كود الإنتاج الفعلي بتاتاً (لا يُستدعى إلا صراحةً من كود الاختبار).
  /// يستبدل الـ adapter في كلا عميلَي Dio الداخليين (`_dio` للطلبات
  /// العادية و`_refreshDio` الخاص بتجديد التوكن).
  @visibleForTesting
  void debugSetHttpClientAdapter(HttpClientAdapter adapter) {
    _dio.httpClientAdapter = adapter;
    _refreshDio.httpClientAdapter = adapter;
  }

  /// نقطة حَقن للاختبار فقط — تتيح فحص/تمهيد التوكنات المخزَّنة مباشرةً.
  @visibleForTesting
  Future<void> debugSeedTokens({
    required String access,
    required String refresh,
  }) async {
    await _SafeStorage.write(key: _accessKey, value: access);
    await _SafeStorage.write(key: _refreshKey, value: refresh);
  }

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
        headers: {'Accept': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _SafeStorage.read(key: _accessKey);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (e, handler) async {
          // 401 → جرّب تجديد التوكن مرة واحدة ثم أعد الطلب
          if (e.response?.statusCode == 401 &&
              e.requestOptions.path != '/token/refresh/' &&
              e.requestOptions.path != '/login/' &&
              e.requestOptions.extra['_retried'] != true) {
            try {
              final newToken = await _refreshAccessToken();
              if (newToken != null) {
                final opts = e.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newToken';
                opts.extra['_retried'] = true;
                final cloneResp = await _dio.fetch(opts);
                return handler.resolve(cloneResp);
              }
              // newToken == null: _refreshAccessToken() نفسها تكفّلت
              // بمسح التوكنات إن كان الرفض نهائياً (401/403)، أو تركتها
              // سليمة إن كان الفشل مؤقتاً بسبب انقطاع الشبكة — لا حاجة
              // لأي إجراء إضافي هنا.
            } on DioException catch (err, st) {
              // فشلت *إعادة* الطلب نفسها بعد نجاح تجديد التوكن — لا
              // نمسح الجلسة إلا إذا كان الرفض من نوع مصادقة قاطع
              // (401/403) فعلاً؛ أي فشل آخر (timeout/connectionError
              // أثناء إعادة المحاولة) يجب ألا يُفقِد المستخدم جلسته
              // الصالحة فعلياً بسبب انقطاع شبكة عابر.
              ErrorHandler.logError(err, st, 'ApiClient.refreshRetry');
              final code = err.response?.statusCode;
              if (code == 401 || code == 403) {
                await clearTokens();
              }
            } catch (err, st) {
              ErrorHandler.logError(err, st, 'ApiClient.refreshRetry');
            }
          }
          handler.next(e);
        },
      ),
    );
  }

  // 🔴 إصلاح ثغرة "الجلسة الزومبي" (Zombie Session Bug — اكتُشفت أثناء
  // تدقيق Pillar 3 لوضع عدم الاتصال والمزامنة التلقائية):
  //
  // كانت `_refreshAccessToken()` تُعامل نوعين مختلفين تماماً من الفشل
  // بنفس الطريقة (مجرد `return null` صامت دون أي تمييز):
  //   1) فشل *مؤقت* بسبب انقطاع الشبكة (DioExceptionType.connectionError/
  //      timeout) — هنا التوكن قد يكون لا يزال صالحاً فعلياً، والمطلوب
  //      الحفاظ عليه لإعادة المحاولة عند عودة الاتصال (سلوك أوفلاين سليم).
  //   2) رفض *نهائي وقاطع* من السيرفر (401/403 على مسار التجديد نفسه)
  //      يعني أن الـ refresh token نفسه أصبح غير صالح تماماً (انتهت
  //      صلاحيته، أو أُبطل يدوياً بعد تغيير كلمة المرور من جهاز آخر، أو
  //      أُلغي الحساب) — لا فائدة إطلاقاً من الاحتفاظ بالـ access token
  //      القديم في هذه الحالة.
  //
  // المشكلة: في كلا الحالتين كانت الدالة تُرجع `null` فقط دون مسح أي
  // توكنات، والـ interceptor في `onError` لا يستدعي `clearTokens()` إلا
  // إذا فشلت *إعادة* الطلب بعد نجاح التجديد (سيناريو نادر جداً) — أي أن
  // `clearTokens()` لم تكن تُستدعى إطلاقاً عند الرفض النهائي الحقيقي.
  // النتيجة: `isAuthenticated()` يستمر بإرجاع `true` إلى الأبد (access
  // token القديم لا يزال مخزَّناً)، فيظن `AuthProvider`/`GradingProvider`
  // أن المستخدم لا يزال مسجَّلاً دخوله بصلاحية سليمة، بينما كل طلب
  // شبكة فعلي (بما فيها `syncGrades` التلقائية عند عودة الاتصال) يفشل
  // بصمت للأبد بلا أي مسار تعافٍ — "جلسة زومبي" لا تعمل ولا تُكتَشف.
  //
  // ✅ الإصلاح: نلتقط `DioException` تحديداً ونميّز صراحةً:
  //   • رفض نهائي (401/403 من مسار /token/refresh/ نفسه) → نمسح كل
  //     التوكنات فوراً (`clearTokens()`) لإجبار حالة "غير مسجَّل دخول"
  //     الصحيحة، بحيث تكتشفها الشاشات التي تراقب `AuthProvider` وتُعيد
  //     توجيه المستخدم لتسجيل الدخول من جديد بدل البقاء في حالة زومبي.
  //   • أي فشل آخر (شبكة/timeout/انقطاع اتصال) → لا نمسح شيئاً إطلاقاً؛
  //     نُبقي التوكنات كما هي تماماً لإتاحة إعادة المحاولة تلقائياً حال
  //     عودة الاتصال، طبقاً لمتطلب "المزامنة التلقائية عند عودة الاتصال".
  Future<String?> _refreshAccessToken() async {
    if (_refreshFuture != null) return _refreshFuture;
    _refreshFuture = (() async {
      try {
        final refresh = await _SafeStorage.read(key: _refreshKey);
        if (refresh == null || refresh.isEmpty) return null;
        final resp = await _refreshDio.post(
          '$baseUrl/token/refresh/',
          data: {'refresh': refresh},
          options: Options(headers: {'Content-Type': 'application/json'}),
        );
        final newAccess = resp.data['access']?.toString();
        if (newAccess != null) {
          await _SafeStorage.write(key: _accessKey, value: newAccess);
          return newAccess;
        }
      } on DioException catch (e, st) {
        ErrorHandler.logError(e, st, 'ApiClient.refreshAccessToken');
        final code = e.response?.statusCode;
        final isDefiniteRejection = code == 401 || code == 403;
        if (isDefiniteRejection) {
          // الـ refresh token نفسه مرفوض نهائياً من السيرفر — لا فائدة
          // من الاحتفاظ بأي توكن قديم، امسح الجلسة بالكامل فوراً.
          await clearTokens();
        }
        // أي نوع آخر (timeout/connectionError/عدم اتصال) → لا نمسح شيئاً،
        // نترك التوكنات سليمة لإعادة المحاولة عند عودة الاتصال.
        return null;
      } catch (e, st) {
        ErrorHandler.logError(e, st, 'ApiClient.refreshAccessToken');
        return null;
      } finally {
        _refreshFuture = null;
      }
      return null;
    })();
    return _refreshFuture;
  }

  /// Exponential-backoff retry للطلبات القابلة للتكرار
  Future<T> _withRetry<T>(
    Future<T> Function() task, {
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 600),
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        return await task();
      } on DioException catch (e) {
        final transient = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.connectionError ||
            (e.response?.statusCode != null && e.response!.statusCode! >= 500);
        if (!transient || attempt >= maxAttempts) rethrow;
        await Future.delayed(baseDelay * attempt);
      }
    }
  }

  // ============ AUTH ============

  Future<Map<String, dynamic>> login(String username, String password) async {
    Response? resp;
    final endpoints = ['/token/', '/login/', '/auth/login/'];
    DioException? lastErr;
    for (final ep in endpoints) {
      try {
        resp = await _dio.post(
          ep,
          data: {'username': username, 'password': password},
          options: Options(headers: {'Content-Type': 'application/json'}),
        );
        break;
      } on DioException catch (e) {
        lastErr = e;
        if (e.response?.statusCode == 401 || e.response?.statusCode == 400) {
          throw _formatError(e);
        }
        // 404/405 → جرّب endpoint التالي
      }
    }
    if (resp == null) throw _formatError(lastErr!);

    final data = Map<String, dynamic>.from(resp.data);
    final access = data['access']?.toString();
    final refresh = data['refresh']?.toString();
    if (access == null || refresh == null) {
      throw 'استجابة غير متوقعة من السيرفر';
    }
    await _SafeStorage.write(key: _accessKey, value: access);
    await _SafeStorage.write(key: _refreshKey, value: refresh);

    User user;
    if (data['user'] is Map) {
      user = User.fromJson(Map<String, dynamic>.from(data['user']));
    } else {
      user = User(id: 0, username: username, email: '', role: 'teacher');
    }
    await _SafeStorage.write(key: _userKey, value: jsonEncode(user.toJson()));
    return {'user': user, 'access': access, 'refresh': refresh};
  }

  Future<void> logout() async {
    try {
      await _dio.post('/logout/');
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'ApiClient.logout');
    }
    await clearTokens();
  }

  Future<void> clearTokens() async {
    await _SafeStorage.delete(key: _accessKey);
    await _SafeStorage.delete(key: _refreshKey);
    await _SafeStorage.delete(key: _userKey);
  }

  Future<bool> isAuthenticated() async {
    final t = await _SafeStorage.read(key: _accessKey);
    return t != null && t.isNotEmpty;
  }

  Future<User?> getCachedUser() async {
    final raw = await _SafeStorage.read(key: _userKey);
    if (raw == null) return null;
    try {
      return User.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'ApiClient.getCachedUser');
      return null;
    }
  }

  // ============ HIERARCHY ============

  Future<List<HierarchyItem>> getHierarchy() async {
    final resp = await _withRetry(() => _dio.get('/hierarchy/'));
    final data = resp.data;
    if (data is List) {
      return data
          .map((e) => HierarchyItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (data is Map && data['hierarchy'] is List) {
      return (data['hierarchy'] as List)
          .whereType<Map>()
          .map((e) => HierarchyItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (data is Map && data['stages'] is List) {
      return (data['stages'] as List)
          .whereType<Map>()
          .map((e) => HierarchyItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  // ============ STUDENTS ============

  Future<ClassroomData> getStudents(
    int classId,
    String subject, {
    String? className,
  }) async {
    final resp = await _withRetry(() => _dio.get(
          '/students/',
          queryParameters: {'class_id': classId, 'subject': subject},
        ));
    final raw = resp.data;
    if (raw is! Map) throw 'استجابة غير متوقعة من السيرفر للطلاب';
    return ClassroomData.fromJson(
      Map<String, dynamic>.from(raw),
      className: className,
      subject: subject,
    );
  }

  // ============ BULK SYNC ============

  Future<Map<String, dynamic>> syncGrades({
    required int termId,
    required int weekNumber,
    required String subject,
    required List<Map<String, dynamic>> grades,
    int? classId,
  }) async {
    final resp = await _withRetry(() => _dio.post(
          '/grades/sync/',
          data: {
            'term_id': termId,
            'week_number': weekNumber,
            'subject': subject,
            if (classId != null) 'class_id': classId,
            'grades': grades,
          },
        ));
    final r = resp.data;
    if (r is Map) return Map<String, dynamic>.from(r);
    return {};
  }

  // ============ SUBSCRIPTION STATUS (Paymob-aware) ============

  /// يجلب حالة الاشتراك "الرسمية" من السيرفر — يُستخدَم للمصالحة
  /// (Reconciliation) بين حالة الاشتراك المحلية (المبنية على أكواد
  /// RSA اليدوية) وأي تحديث فوري وصل عبر Webhook من بوابة الدفع
  /// (Paymob) مباشرةً إلى السيرفر دون المرور بالتطبيق إطلاقاً.
  ///
  /// العقد المتوقَّع من الـ endpoint `/subscription/status/` (GET، يتطلب
  /// JWT صالح — نفس آلية المصادقة المستخدمة في بقية الـ API):
  /// ```json
  /// {
  ///   "plan": "pro",            // free | basic | pro | school
  ///   "is_active": true,
  ///   "is_trial": false,
  ///   "expiry_date": "2026-03-01T00:00:00Z",  // أو null لاشتراك دائم
  ///   "start_date": "2026-02-01T00:00:00Z"
  /// }
  /// ```
  /// يُعيد null بأمان (بدل رمي استثناء) عند أي فشل في الاتصال أو صيغة
  /// غير متوقعة — هذا المسار "تحسيني" فقط (Best-effort)، ولا يجب أبداً
  /// أن يمنع التطبيق من العمل بحالة الاشتراك المحلية الموجودة أصلاً في
  /// حال تعذّر الوصول للسيرفر (أونلاين متقطع، السيرفر متوقف مؤقتاً...).
  Future<Map<String, dynamic>?> getSubscriptionStatus() async {
    try {
      final resp = await _dio.get('/subscription/status/');
      final data = resp.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'ApiClient.getSubscriptionStatus');
      return null;
    }
  }

  // ============ ACTIVATION CODE REDEMPTION REGISTRY ============
  //
  // 🔴 ثغرة تجارية جسيمة تم اكتشافها أثناء تدقيق Pillar 2 (أخطر من مجرد
  // إساءة استخدام كود تجربة مجانية): تتبع "الأكواد المُستخدَمة" بالكامل
  // (`used_activation_codes` في SubscriptionService) يعيش فقط داخل
  // SharedPreferences المحلية — وهي تُمسَح بالكامل عند حذف التطبيق
  // وإعادة تثبيته. في المقابل، معرّف الجهاز (`getDeviceId()`، المبني على
  // ANDROID_ID الثابت) **يبقى كما هو** عبر إعادة التثبيت. النتيجة: أي
  // كود — سواء كان كود تجربة مجانية أو حتى **كود RSA مدفوع حقيقي اشتراه
  // العميل فعلياً** — يمكن إعادة "تفعيله" إلى ما لا نهاية بمجرد حذف
  // التطبيق وإعادة تثبيته في كل مرة يقترب فيها من الانتهاء، دون أي دفعة
  // إضافية حقيقية.
  //
  // ✅ الإصلاح (Best-Effort Server-Side Registry): بما أن التطبيق مصمَّم
  // ليعمل بكامل وظائفه في وضع أوفلاين تام (بما في ذلك تفعيل كود مدفوع
  // لأول مرة لدى معلم في منطقة بلا إنترنت لحظة التفعيل)، لا يصح جعل
  // التحقق من السيرفر شرطاً إلزامياً يمنع التفعيل بالكامل. بدلاً من ذلك:
  // يُسجَّل كل استخدام كود على السيرفر (best-effort) بربط
  // hash(code) ⇄ device_id، ويُرفَض فقط إذا كان السيرفر متصلاً *وأكد
  // صراحةً* أن نفس الكود سبق استخدامه من جهاز *آخر* مختلف تماماً. لو
  // تعذّر الوصول للسيرفر إطلاقاً (أوفلاين حقيقي)، يُكمَل التفعيل بالاعتماد
  // على الفحص المحلي القديم كما هو (سلوك متدرِّج/Graceful Degradation —
  // لا يتراجع أبداً عن أي قدرة أوفلاين موجودة مسبقاً).
  //
  // العقد المتوقَّع من `/subscription/redeem/` (POST، JWT اختياري — يمكن
  // أن يعمل بدون تسجيل دخول لأن أكواد التفعيل مستقلة عن حساب المستخدم):
  //   Request:  { "code_hash": "<sha256>", "device_id": "<ANDROID_ID>" }
  //   Response 200: { "status": "ok" }                — مسموح (جهاز جديد
  //                                                      لهذا الكود، أو
  //                                                      نفس الجهاز يُعيد
  //                                                      إرسال نفس الطلب)
  //   Response 200/409: { "status": "already_used" }  — مرفوض: الكود
  //                                                      مُسجَّل بالفعل
  //                                                      لجهاز آخر مختلف
  //
  /// يُسجِّل (best-effort) استخدام كود تفعيل مرتبطاً بمعرّف جهاز معيّن.
  ///
  /// يُعيد:
  ///  - `true`  إذا أكّد السيرفر أن هذا الاستخدام مسموح (جهاز جديد لهذا
  ///    الكود، أو نفس الجهاز الذي استخدمه سابقاً).
  ///  - `false` إذا أكّد السيرفر صراحةً أن الكود مُستخدَم بالفعل من جهاز
  ///    *آخر* — رفض قاطع وواضح.
  ///  - `null`  إذا تعذّر الوصول للسيرفر بالكامل (بلا إنترنت، أو السيرفر
  ///    متوقف) — يعني "غير معروف"، والمُستدعي يجب أن يعتمد حينها على أي
  ///    فحص محلي احتياطي متاح (Graceful Degradation، وليس رفضاً تلقائياً).
  Future<bool?> redeemActivationCode({
    required String codeHash,
    required String deviceId,
  }) async {
    try {
      final resp = await _dio.post(
        '/subscription/redeem/',
        data: {'code_hash': codeHash, 'device_id': deviceId},
      );
      final data = resp.data;
      if (data is Map && data['status'] == 'already_used') return false;
      return true;
    } on DioException catch (e, st) {
      // 409 Conflict صريح من السيرفر = مرفوض بشكل قاطع (وليس فشل اتصال)
      if (e.response?.statusCode == 409) return false;
      final data = e.response?.data;
      if (data is Map && data['status'] == 'already_used') return false;
      // أي خطأ اتصال آخر (Timeout/DNS/عدم توفر السيرفر) = "غير معروف"
      ErrorHandler.logError(e, st, 'ApiClient.redeemActivationCode');
      return null;
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'ApiClient.redeemActivationCode');
      return null;
    }
  }

  // ============ VOICE TRANSCRIBE ============

  Future<String> transcribeAudio(String filePath) async {
    // Web platform لا تدعم dart:io File
    if (kIsWeb) {
      throw 'تحويل الصوت لنص عبر السيرفر غير متاح على متصفح الويب.\n'
          'استخدم التطبيق على الهاتف للحصول على هذه الميزة.';
    }

    if (!File(filePath).existsSync()) {
      throw 'الملف الصوتي غير موجود';
    }

    return _withRetry(() async {
      final form = FormData.fromMap({
        'audio': await MultipartFile.fromFile(
          filePath,
          filename: filePath.split('/').last,
        ),
      });
      final resp = await _dio.post(
        '/voice/transcribe/',
        data: form,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 90),
        ),
      );
      final d = resp.data;
      if (d is Map) {
        return (d['transcript'] ?? d['text'] ?? '').toString();
      }
      return '';
    });
  }

  // ============ ERROR FORMATTING ============

  String _formatError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return 'انتهت مهلة الاتصال بالسيرفر';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'تعذر الاتصال بالسيرفر، تحقق من الإنترنت';
    }
    final code = e.response?.statusCode;
    final data = e.response?.data;
    if (code == 401 || code == 400) {
      String msg = 'بيانات الدخول غير صحيحة';
      if (data is Map) {
        msg = data['detail']?.toString() ??
            data['error']?.toString() ??
            data['message']?.toString() ??
            msg;
      }
      return msg;
    }
    if (code == 403) return 'ليس لديك صلاحية الوصول';
    if (code == 404) return 'العنوان غير موجود على السيرفر';
    if (code != null && code >= 500) return 'خطأ في السيرفر ($code)';
    if (data is Map) {
      return data['detail']?.toString() ??
          data['error']?.toString() ??
          'حدث خطأ في السيرفر (${code ?? '?'})';
    }
    return 'حدث خطأ غير متوقع';
  }
}

/// Singleton accessor
final ApiClient apiClient = ApiClient();
