// اختبار حي (Live Functional Test) لإصلاح ثغرة "الجلسة الزومبي"
// (Zombie Session Bug) في ApiClient._refreshAccessToken() + onError
// interceptor — اكتُشفت أثناء تدقيق Pillar 3 لوضع عدم الاتصال (Hive)
// والمزامنة التلقائية.
//
// 🔴 المشكلة الأصلية المُكتشَفة:
// كانت `_refreshAccessToken()` تُعامل نوعين مختلفين تماماً من فشل طلب
// تجديد التوكن (`POST /token/refresh/`) بنفس الطريقة تماماً — مجرد
// `return null` صامت دون أي تمييز أو أي تنظيف للحالة:
//   1) رفض *نهائي وقاطع* من السيرفر (401/403) يعني أن الـ refresh
//      token نفسه أصبح غير صالح تماماً (منتهي الصلاحية، أو أُبطل بعد
//      تغيير كلمة المرور من جهاز آخر، أو أُلغي الحساب بالكامل).
//   2) فشل *مؤقت* بسبب انقطاع الشبكة (timeout/connectionError) — هنا
//      التوكن قد يكون لا يزال صالحاً فعلياً تماماً.
//
// في كلا الحالتين لم تكن `clearTokens()` تُستدعى إطلاقاً من داخل
// `_refreshAccessToken()` نفسها، والـ interceptor في `onError` كان
// يستدعيها فقط إذا فشلت *إعادة* الطلب الأصلي بعد نجاح تجديد التوكن
// (سيناريو نادر جداً لا علاقة له بالرفض الفعلي لطلب التجديد). النتيجة:
// عند رفض السيرفر النهائي لـ refresh token، يستمر `isAuthenticated()`
// بإرجاع `true` إلى الأبد لأن الـ access token القديم يبقى مخزَّناً
// دون أي مسح — "جلسة زومبي" يظن فيها `AuthProvider`/`GradingProvider`
// أن المستخدم مسجَّل دخوله بصلاحية سليمة، بينما كل طلب شبكة فعلي (بما
// فيها مزامنة الدرجات المعلّقة التلقائية عند عودة الاتصال) يفشل بصمت
// للأبد بلا أي مسار تعافٍ ودون أن يُطلَب من المستخدم إعادة تسجيل
// الدخول لحل المشكلة.
//
// ✅ الإصلاح: تمييز صريح داخل `_refreshAccessToken()` (وأيضاً داخل
// `onError` عند فشل إعادة الطلب بعد التجديد):
//   • رفض نهائي (401/403 من مسار /token/refresh/ نفسه، أو من إعادة
//     الطلب الأصلي بعد التجديد) → `clearTokens()` فوراً لإجبار حالة
//     "غير مسجَّل دخول" الصحيحة.
//   • أي فشل آخر (شبكة/timeout/انقطاع اتصال) → لا نمسح شيئاً إطلاقاً؛
//     التوكنات تبقى سليمة لإعادة المحاولة تلقائياً عند عودة الاتصال.
//
// هذا الملف يختبر السلوكين معاً بشكل حتمي (deterministic) دون أي اتصال
// شبكة حقيقي، عبر:
//   1) محاكاة قناة `flutter_secure_storage` (MethodChannel) بخريطة
//      داخلية بسيطة (In-memory fake) — تُحاكي التخزين الآمن الحقيقي
//      لكن بدون أي اعتماد على منصة أصلية (native) غير متاحة في بيئة
//      `flutter test` (Dart VM).
//   2) حقن `HttpClientAdapter` وهمي في `ApiClient` عبر نقطة الاختبار
//      الجديدة `debugSetHttpClientAdapter()` — يُرجع استجابات HTTP
//      حتمية (401/403 أو استثناء اتصال) دون أي طلب شبكة فعلي.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/services/api_client.dart';

/// محاكاة بسيطة لقناة `flutter_secure_storage` الأصلية باستخدام خريطة
/// داخلية (In-memory) — تسمح لاختبارات `ApiClient` بالعمل بشكل حتمي
/// تماماً دون أي اعتماد على منصة أصلية (native) في بيئة `flutter test`.
class _FakeSecureStorageChannel {
  final Map<String, String> store = {};
  static const _channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
      switch (call.method) {
        case 'write':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          return store[args['key'] as String];
        case 'delete':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          store.remove(args['key'] as String);
          return null;
        case 'deleteAll':
          store.clear();
          return null;
        case 'readAll':
          return store;
        case 'containsKey':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          return store.containsKey(args['key'] as String);
        default:
          return null;
      }
    });
  }
}

/// محوّل HTTP وهمي (Fake [HttpClientAdapter]) يُميّز بين نوعين من
/// الطلبات بدقة، تماماً كما يحدث في السيناريو الحقيقي:
///   • أي طلب عادي (مثل `/hierarchy/`) → يُرجع دائماً 401 (توكن منتهي)
///     لتفعيل مسار "تجديد التوكن" داخل الـ onError interceptor بالضبط
///     كما يحدث في الإنتاج الحقيقي.
///   • طلب `/token/refresh/` تحديداً → يُرجع النتيجة القابلة للتحكم بها
///     صراحةً من الاختبار ([refreshStatusCode] أو استثناء اتصال) لمحاكاة
///     "رفض نهائي" أو "انقطاع شبكة مؤقت" أثناء تجديد التوكن نفسه.
class _FakeRefreshAdapter implements HttpClientAdapter {
  _FakeRefreshAdapter({
    required this.refreshStatusCode,
    this.throwConnectionErrorOnRefresh = false,
  });

  final int refreshStatusCode;
  final bool throwConnectionErrorOnRefresh;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final isRefreshEndpoint = options.path.contains('/token/refresh/');

    if (!isRefreshEndpoint) {
      // أي طلب عادي آخر → دائماً 401 (توكن قديم/منتهي) لتفعيل مسار
      // التجديد في onError interceptor، مطابقاً للسيناريو الحقيقي.
      return ResponseBody.fromString(
        '{}',
        401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    // طلب تجديد التوكن تحديداً:
    if (throwConnectionErrorOnRefresh) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Simulated network drop during token refresh (test)',
      );
    }
    return ResponseBody.fromString(
      refreshStatusCode >= 200 && refreshStatusCode < 300
          ? '{"access":"new_access_token"}'
          : '{}',
      refreshStatusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStorageChannel fakeSecureStorage;

  setUp(() {
    fakeSecureStorage = _FakeSecureStorageChannel()..install();
  });

  group('🔴 ثغرة الجلسة الزومبي (Zombie Session Bug)', () {
    test(
      'رفض نهائي (401) على /token/refresh/ → يجب مسح كل التوكنات فوراً',
      () async {
        final client = ApiClient();
        await client.debugSeedTokens(
            access: 'old_access', refresh: 'old_refresh');

        // تأكيد ما قبل: الجلسة "مصادَق عليها" (access token موجود)
        expect(await client.isAuthenticated(), isTrue);

        // نحقن adapter وهمي يرفض طلب تجديد التوكن برفض HTTP 401 قاطع
        client.debugSetHttpClientAdapter(
          _FakeRefreshAdapter(refreshStatusCode: 401),
        );

        // نستدعي مسار داخلي يُطلِق _refreshAccessToken() فعلياً: أبسط
        // طريقة متاحة من الخارج هي محاولة استدعاء endpoint محمي عادي
        // (مثل getHierarchy) الذي سيحصل أولاً على استجابة 401 وهمية من
        // نفس الـ adapter (لأن كل الطلبات تمر عبر نفس المحوّل الوهمي)،
        // فيُشغِّل الـ onError interceptor مسار التجديد بالضبط كما في
        // الإنتاج الحقيقي.
        try {
          await client.getHierarchy();
        } catch (_) {
          // متوقع: فشل الطلب الأصلي نفسه أيضاً (نفس الـ adapter الوهمي
          // يرفض كل الطلبات بـ 401) — هذا جزء طبيعي من السيناريو، ما
          // يهمّنا هو الأثر الجانبي (مسح التوكنات) لا نتيجة هذا الطلب.
        }

        // ✅ التحقق الحاسم: يجب أن تُمسَح كل التوكنات المخزَّنة بعد
        // الرفض النهائي — لا يجب أن تبقى "جلسة زومبي" صالحة ظاهرياً.
        expect(await client.isAuthenticated(), isFalse);
        expect(fakeSecureStorage.store.containsKey('access_token'), isFalse);
        expect(fakeSecureStorage.store.containsKey('refresh_token'), isFalse);
      },
    );

    test(
      'رفض نهائي (403) على /token/refresh/ → يجب مسح كل التوكنات فوراً',
      () async {
        final client = ApiClient();
        await client.debugSeedTokens(
            access: 'old_access', refresh: 'old_refresh');
        expect(await client.isAuthenticated(), isTrue);

        client.debugSetHttpClientAdapter(
          _FakeRefreshAdapter(refreshStatusCode: 403),
        );

        try {
          await client.getHierarchy();
        } catch (_) {}

        expect(await client.isAuthenticated(), isFalse);
      },
    );

    test(
      'انقطاع شبكة مؤقت أثناء تجديد التوكن → يجب الحفاظ على التوكنات '
      '(عدم تسجيل خروج المستخدم بسبب مشكلة اتصال عابرة)',
      () async {
        final client = ApiClient();
        await client.debugSeedTokens(
            access: 'old_access', refresh: 'old_refresh');
        expect(await client.isAuthenticated(), isTrue);

        // كل الطلبات (بما فيها طلب التجديد) تفشل باستثناء اتصال —
        // يُحاكي انقطاع الإنترنت الفعلي، وليس رفضاً من السيرفر.
        client.debugSetHttpClientAdapter(
          _FakeRefreshAdapter(
            refreshStatusCode: 0,
            throwConnectionErrorOnRefresh: true,
          ),
        );

        try {
          await client.getHierarchy();
        } catch (_) {
          // متوقع فشل الطلب نفسه بسبب انقطاع الشبكة المحاكى.
        }

        // ✅ التحقق الحاسم: التوكنات يجب أن تبقى سليمة تماماً — لا مسح
        // إطلاقاً بسبب انقطاع اتصال مؤقت، حفاظاً على قابلية إعادة
        // المحاولة التلقائية فور عودة الاتصال (متطلب Pillar 3).
        expect(await client.isAuthenticated(), isTrue);
        expect(fakeSecureStorage.store['access_token'], 'old_access');
        expect(fakeSecureStorage.store['refresh_token'], 'old_refresh');
      },
    );
  });
}
