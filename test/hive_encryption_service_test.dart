// اختبار حي فعلي (Live Functional Test) لـ HiveEncryptionService — الإصلاح
// الأمني الخاص بـ Task 3 (تشفير قاعدة البيانات المحلية Hive بـ AES-256).
//
// 🔴 المشكلة الأصلية: كانت جميع صناديق Hive في التطبيق (بيانات الطلاب/
// الدرجات المعلّقة، حسابات المستخدمين وكلمات مرورهم المُجزَّأة، سجل
// النشاطات، إعدادات النظام) تُخزَّن كملفات `.hive` عادية غير مشفَّرة على
// نظام ملفات الجهاز — قابلة للاستخراج والقراءة المباشرة عبر أدوات ADB أو
// نسخة احتياطية لجهاز مكسور الحماية، دون أي حاجة لكسر كلمة مرور التطبيق.
//
// ✅ الإصلاح: `HiveEncryptionService` يُطبِّق تشفير AES-256 (HiveAesCipher)
// على كل الصناديق عبر مفتاح 32 بايت مُولَّد عشوائياً ومخزَّن بأمان
// (FlutterSecureStorage)، مع ترحيل تلقائي آمن وشفاف لأي صندوق قديم يحوي
// بيانات غير مشفَّرة من إصدار سابق للتطبيق — بلا أي فقدان بيانات.
//
// هذا الاختبار يحاكي قناة flutter_secure_storage (MethodChannel) بخريطة
// داخلية بسيطة (In-memory Fake) تماماً كما في api_client_zombie_session_
// test.dart، ليعمل بشكل حتمي دون أي اعتماد على منصة أصلية غير متاحة في
// بيئة `flutter test` (Dart VM).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_grades_voice/services/hive_encryption_service.dart';

/// محاكاة بسيطة لقناة `flutter_secure_storage` الأصلية باستخدام خريطة
/// داخلية — نفس النمط المستخدَم في api_client_zombie_session_test.dart.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late _FakeSecureStorageChannel fakeSecureStorage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_encryption_test_');
    Hive.init(tempDir.path);
    fakeSecureStorage = _FakeSecureStorageChannel();
    fakeSecureStorage.install();
    SharedPreferences.setMockInitialValues({});
    // إعادة تصفير الحالة الداخلية المخبَّأة (cachedCipher) بين الاختبارات
    // عبر تابع الاختبار المخصَّص @visibleForTesting.
    HiveEncryptionService.resetCacheForTesting();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('يفتح صندوقاً جديداً مشفَّراً ويكتب/يقرأ البيانات بنجاح', () async {
    final box = await HiveEncryptionService.openEncryptedBox('fresh_box');
    await box.put('name', 'Ahmed');
    await box.put('grade', 95);
    expect(box.get('name'), 'Ahmed');
    expect(box.get('grade'), 95);
    await box.close();
  });

  test(
      'تكامل التشفير (Round-trip): البيانات المكتوبة قبل إعادة فتح '
      'التطبيق تُقرأ بنجاح بعد إعادة الفتح بنفس المفتاح المخزَّن', () async {
    // "تشغيل أول" للتطبيق
    final box1 = await HiveEncryptionService.openEncryptedBox('roundtrip_box');
    await box1.put(
      'student_1',
      jsonEncode({'name': 'سارة', 'grade': 88}),
    );
    await box1.close();

    // محاكاة "إعادة تشغيل التطبيق" — نُصفِّر cache الـ cipher الداخلي
    // (كما لو كانت عملية جديدة تماماً) لكن نُبقي على نفس _FakeSecureStorageChannel
    // (يحاكي أن المفتاح لا يزال محفوظاً في التخزين الآمن الحقيقي بين التشغيلتين).
    HiveEncryptionService.resetCacheForTesting();

    final box2 = await HiveEncryptionService.openEncryptedBox('roundtrip_box');
    final raw = box2.get('student_1') as String?;
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded['name'], 'سارة');
    expect(decoded['grade'], 88);
    await box2.close();
  });

  test(
      'الترحيل الآمن (Migration): صندوق قديم غير مشفَّر يُرحَّل تلقائياً '
      'دون أي فقدان بيانات، ويصبح مشفَّراً فعلياً بعد الترحيل', () async {
    // محاكاة "بيانات قديمة" أُنشئت قبل تفعيل التشفير — فتح عادي بلا cipher
    final legacyBox = await Hive.openBox('legacy_box');
    await legacyBox.put('pending_1', jsonEncode({'studentId': 7, 'score': 42}));
    await legacyBox.put('pending_2', jsonEncode({'studentId': 8, 'score': 51}));
    await legacyBox.close();

    // الآن نطلب فتحه عبر الخدمة المشفَّرة — يجب أن يكتشف فشل الفتح
    // المباشر بالـ cipher ويُرحِّل البيانات تلقائياً وبأمان.
    final migratedBox =
        await HiveEncryptionService.openEncryptedBox('legacy_box');

    // كل البيانات القديمة يجب أن تكون محفوظة بالكامل بعد الترحيل
    expect(migratedBox.get('pending_1'),
        jsonEncode({'studentId': 7, 'score': 42}));
    expect(migratedBox.get('pending_2'),
        jsonEncode({'studentId': 8, 'score': 51}));
    await migratedBox.close();

    // ✅ التحقق الحاسم: الصندوق أصبح فعلياً مشفَّراً على القرص الآن —
    // نتحقق مباشرةً من محتوى ملف `.hive` الخام: يجب ألا يحوي إطلاقاً
    // النص الصريح لأي من قيم JSON المكتوبة أصلاً (لو كانت البيانات لا
    // تزال غير مشفَّرة، لكانت هذه السلاسل النصية ظاهرة بوضوح كـ plaintext
    // داخل الملف الخام). هذا تحقّق مباشر وحتمي من حدوث التشفير الفعلي،
    // دون الاعتماد على مسارات معالجة الأخطاء الداخلية غير المستقرة في
    // مكتبة Hive نفسها عند محاولة إعادة فتح صندوق مشفَّر بلا cipher.
    final rawFile = File('${tempDir.path}/legacy_box.hive');
    expect(await rawFile.exists(), isTrue);
    final rawBytes = await rawFile.readAsString(encoding: latin1);
    expect(rawBytes.contains('studentId'), isFalse);
    expect(rawBytes.contains('score'), isFalse);
  });

  test('لا يُعيد فتح صندوق مفتوح بالفعل (يتجنب تعارض الـ cipher)', () async {
    final box1 = await HiveEncryptionService.openEncryptedBox('idempotent_box');
    await box1.put('k', 'v1');

    // استدعاء ثانٍ لنفس الاسم بينما الصندوق لا يزال مفتوحاً — يجب أن
    // يُرجع نفس المثيل المفتوح دون محاولة إعادة فتحه بأي cipher جديد.
    final box2 = await HiveEncryptionService.openEncryptedBox('idempotent_box');
    expect(identical(box1, box2), isTrue);
    expect(box2.get('k'), 'v1');
    await box2.close();
  });
}
