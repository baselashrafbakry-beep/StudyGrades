import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import '../models/user_model.dart';
import '../utils/error_handler.dart';

/// خدمة إدارة المستخدمين والإعدادات الإدارية محلياً
/// تعمل في وضع Offline بشكل كامل وتُمكّن المطور والمدير من إدارة الحسابات
class AdminService {
  static const String _usersBox = 'admin_users_box';
  static const String _settingsBox = 'admin_settings_box';
  static const String _activityBox = 'admin_activity_box';

  /// إنشاء/فتح صناديق Hive
  static Future<void> ensureOpen() async {
    if (!Hive.isBoxOpen(_usersBox)) {
      await Hive.openBox(_usersBox);
    }
    if (!Hive.isBoxOpen(_settingsBox)) {
      await Hive.openBox(_settingsBox);
    }
    if (!Hive.isBoxOpen(_activityBox)) {
      await Hive.openBox(_activityBox);
    }
  }

  // ─────────────────── إدارة المستخدمين ───────────────────

  // ═══════════════════════════════════════════════════════
  // بيانات المطور الرسمية — م. باسل أشرف
  // ═══════════════════════════════════════════════════════
  static const String developerName     = 'م. باسل أشرف';
  static const String developerUsername = 'basel';
  static const String developerEmail    = 'baselashraf.bakry@gmail.com';
  static const String developerPhone    = '01014543845';
  static const String developerWhatsApp = 'https://wa.me/201014543845';
  static const String appVersion        = '2.0.0';
  static const String appName           = 'Study Grades Voice';
  static const String appNameAr         = 'نظام رصد الدرجات الصوتي';
  static const String copyrightYear     = '2026';
  static const String packageName       = 'com.myapp.mobile';
  static const String serverUrl         = 'studygrades2026.pythonanywhere.com';
  static const String serverUrlFull     = 'https://studygrades2026.pythonanywhere.com';

  /// تهيئة الحساب الافتراضي للمطور (يتم استدعاؤها عند البدء)
  static Future<void> initDefaultDeveloper() async {
    await ensureOpen();
    final box = Hive.box(_usersBox);
    if (box.isEmpty) {
      // حساب المطور الرسمي - م. باسل أشرف
      final developer = User(
        id: 1,
        username: developerUsername,
        email: developerEmail,
        role: UserRole.developer,
        fullName: developerName,
        phone: developerPhone,
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );
      // ملاحظة أمنية: يُنصح بشدة بتغيير كلمة المرور الافتراضية فور أول
      // دخول عبر شاشة "إدارة المستخدمين" → "إعادة تعيين كلمة المرور"،
      // لأن كلمات المرور الافتراضية المكتوبة في الكود المصدري قد تكون
      // قابلة للاستخلاص من ملف APK المُفكَّك في حالات نادرة.
      await _saveUserDirect(developer, password: 'Basel@2026');
      await logActivity('تهيئة النظام', 'تم تهيئة $appName v$appVersion بنجاح');
    } else {
      // تحديث بيانات المطور إذا تغيرت
      final existingRaw = box.get('1') as String?;
      if (existingRaw != null) {
        try {
          final existing = jsonDecode(existingRaw) as Map<String, dynamic>;
          if (existing['email'] != developerEmail ||
              existing['phone'] != developerPhone ||
              existing['full_name'] != developerName) {
            final updated = User.fromJson(existing).copyWith(
              email: developerEmail,
              phone: developerPhone,
              fullName: developerName,
            );
            await _saveUserDirect(updated);
          }
        } catch (_) {}
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // نظام تشفير كلمات المرور — SHA-256 + Salt عشوائي لكل مستخدم
  // (أقوى من base64 القديم؛ base64 ليس تشفيراً بل ترميزاً فقط
  // ويمكن فك تشفيره فوراً بدون أي مفتاح)
  // ═══════════════════════════════════════════════════════
  static String _generateSalt() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64Encode(bytes);
  }

  static String _hashPassword(String password, String salt) {
    final bytes = utf8.encode('$salt:$password');
    return sha256.convert(bytes).toString();
  }

  /// حفظ مستخدم مع كلمة المرور (SHA-256 + Salt عشوائي فريد لكل مستخدم)
  static Future<void> _saveUserDirect(User user, {String? password}) async {
    final box = Hive.box(_usersBox);
    final data = user.toJson();
    if (password != null) {
      final salt = _generateSalt();
      data['password_salt'] = salt;
      data['password_hash'] = _hashPassword(password, salt);
    } else {
      // إن لم تُمرر كلمة مرور، احتفظ بالقديمة إن وُجدت (hash + salt)
      final existing = box.get(user.id.toString());
      if (existing != null) {
        final prev = jsonDecode(existing as String) as Map<String, dynamic>;
        data['password_hash'] = prev['password_hash'];
        data['password_salt'] = prev['password_salt'];
      }
    }
    await box.put(user.id.toString(), jsonEncode(data));
  }

  /// جلب جميع المستخدمين
  static Future<List<User>> getAllUsers() async {
    await ensureOpen();
    final box = Hive.box(_usersBox);
    final users = <User>[];
    for (final key in box.keys) {
      try {
        final raw = box.get(key);
        if (raw == null) continue;
        final data = jsonDecode(raw as String) as Map<String, dynamic>;
        users.add(User.fromJson(data));
      } catch (e, st) {
        ErrorHandler.logError(e, st, 'AdminService.listUsers');
      }
    }
    users.sort((a, b) => UserRole.level(b.role) - UserRole.level(a.role));
    return users;
  }

  /// إنشاء مستخدم جديد
  static Future<User> createUser({
    required String username,
    required String password,
    required String email,
    required String role,
    String fullName = '',
    String? phone,
  }) async {
    await ensureOpen();
    final users = await getAllUsers();

    // التحقق من عدم تكرار اسم المستخدم
    if (users.any((u) => u.username.toLowerCase() == username.toLowerCase())) {
      throw Exception('اسم المستخدم موجود بالفعل');
    }
    if (email.isNotEmpty &&
        users.any((u) => u.email.toLowerCase() == email.toLowerCase())) {
      throw Exception('البريد الإلكتروني مستخدم بالفعل');
    }

    final newId =
        users.isEmpty ? 2 : (users.map((u) => u.id).reduce((a, b) => a > b ? a : b) + 1);

    final user = User(
      id: newId,
      username: username,
      email: email,
      role: role,
      fullName: fullName,
      phone: phone,
      isActive: true,
      createdAt: DateTime.now(),
    );

    await _saveUserDirect(user, password: password);
    await logActivity(
      'إنشاء حساب',
      'تم إنشاء حساب جديد: $username (${UserRole.label(role)})',
    );
    return user;
  }

  /// تعديل مستخدم
  static Future<User> updateUser(
    User user, {
    String? newPassword,
  }) async {
    await ensureOpen();
    await _saveUserDirect(user, password: newPassword);
    await logActivity(
      'تعديل حساب',
      'تم تعديل بيانات: ${user.username}',
    );
    return user;
  }

  /// حذف مستخدم
  static Future<void> deleteUser(int userId) async {
    await ensureOpen();
    final box = Hive.box(_usersBox);
    final user = await getUserById(userId);
    await box.delete(userId.toString());
    if (user != null) {
      await logActivity(
        'حذف حساب',
        'تم حذف الحساب: ${user.username}',
      );
    }
  }

  /// تفعيل/تعطيل حساب
  static Future<void> toggleUserActive(int userId) async {
    final user = await getUserById(userId);
    if (user == null) return;
    final updated = user.copyWith(isActive: !user.isActive);
    await _saveUserDirect(updated);
    await logActivity(
      updated.isActive ? 'تفعيل' : 'تجميد',
      '${updated.isActive ? 'تم تفعيل' : 'تم تجميد'} حساب: ${updated.username}',
    );
  }

  /// إعادة تعيين كلمة المرور
  static Future<void> resetPassword(int userId, String newPassword) async {
    final user = await getUserById(userId);
    if (user == null) return;
    await _saveUserDirect(user, password: newPassword);
    await logActivity(
      'تغيير كلمة المرور',
      'تم تغيير كلمة المرور لـ: ${user.username}',
    );
  }

  /// جلب مستخدم بواسطة ID
  static Future<User?> getUserById(int userId) async {
    await ensureOpen();
    final box = Hive.box(_usersBox);
    final raw = box.get(userId.toString());
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      return User.fromJson(data);
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'AdminService.getUserById');
      return null;
    }
  }

  /// التحقق من بيانات تسجيل الدخول محلياً (للاستخدام كـ fallback)
  /// يدعم صيغة SHA-256+Salt الجديدة، مع ترحيل تلقائي وشفاف لأي حساب
  /// قديم لا يزال مخزَّناً بصيغة base64 (النظام السابق) عند أول دخول ناجح.
  static Future<User?> verifyCredentials(
    String username,
    String password,
  ) async {
    await ensureOpen();
    final box = Hive.box(_usersBox);
    // صيغة قديمة (base64) — للتوافق العكسي فقط، تُرحَّل تلقائياً بعد أول دخول
    final legacyHash = base64Encode(utf8.encode(password));
    for (final key in box.keys) {
      try {
        final raw = box.get(key);
        if (raw == null) continue;
        final data = jsonDecode(raw as String) as Map<String, dynamic>;
        final dbUsername = (data['username'] ?? '').toString().toLowerCase();
        if (dbUsername != username.toLowerCase()) continue;

        final dbHash = data['password_hash']?.toString() ?? '';
        final dbSalt = data['password_salt']?.toString();

        bool matched = false;
        if (dbSalt != null && dbSalt.isNotEmpty) {
          // الصيغة الجديدة الآمنة: SHA-256(salt + password)
          matched = _hashPassword(password, dbSalt) == dbHash;
        } else {
          // الصيغة القديمة: base64 فقط (لحسابات أُنشئت قبل هذا التحديث)
          matched = dbHash == legacyHash;
        }

        if (matched) {
          // فحص الحالة أولاً قبل تحديث آخر دخول
          final user = User.fromJson(data);
          if (!user.isActive) {
            throw Exception('هذا الحساب موقوف. تواصل مع المدير.');
          }
          // تحديث آخر دخول، وترحيل تلقائي إلى الصيغة الآمنة الجديدة
          // إذا كان الحساب لا يزال يستخدم base64 القديم
          final updated = user.copyWith(lastLogin: DateTime.now());
          if (dbSalt == null || dbSalt.isEmpty) {
            await _saveUserDirect(updated, password: password);
          } else {
            await _saveUserDirect(updated);
          }
          return updated;
        }
      } catch (e) {
        if (e.toString().contains('موقوف')) rethrow;
        // تجاهل أخطاء JSON parsing للمفاتيح الأخرى
      }
    }
    return null;
  }

  // ─────────────────── سجل النشاطات ───────────────────

  static Future<void> logActivity(String type, String description) async {
    await ensureOpen();
    final box = Hive.box(_activityBox);
    final entry = {
      'type': type,
      'description': description,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await box.add(jsonEncode(entry));

    // الحفاظ على آخر 200 نشاط فقط
    if (box.length > 200) {
      final keysToRemove = box.keys.toList().sublist(0, box.length - 200);
      await box.deleteAll(keysToRemove);
    }
  }

  static Future<List<Map<String, dynamic>>> getActivityLog() async {
    await ensureOpen();
    final box = Hive.box(_activityBox);
    final entries = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      try {
        final raw = box.get(key);
        if (raw == null) continue;
        entries.add(jsonDecode(raw as String) as Map<String, dynamic>);
      } catch (e, st) {
        ErrorHandler.logError(e, st, 'AdminService.listActivities');
      }
    }
    entries.sort((a, b) =>
        (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));
    return entries;
  }

  static Future<void> clearActivityLog() async {
    await ensureOpen();
    final box = Hive.box(_activityBox);
    await box.clear();
  }

  // ─────────────────── إعدادات النظام ───────────────────

  static Future<T?> getSystemSetting<T>(String key, {T? defaultValue}) async {
    await ensureOpen();
    final box = Hive.box(_settingsBox);
    final value = box.get(key);
    if (value == null) return defaultValue;
    return value as T?;
  }

  static Future<void> setSystemSetting(String key, dynamic value) async {
    await ensureOpen();
    final box = Hive.box(_settingsBox);
    await box.put(key, value);
    await logActivity('إعدادات النظام', 'تم تعديل: $key');
  }

  // ─────────── إعدادات النظام: دوال مساعدة (Feature Flags) ───────────
  // هذه الدوال تُستخدم في جميع أنحاء التطبيق لفرض احترام مفاتيح التحكم
  // التي يُفعّلها/يُعطّلها المطور من شاشة "إعدادات النظام"، بدلاً من ترك
  // هذه المفاتيح شكلية بلا أي تأثير فعلي.
  static Future<bool> isServerSpeechEnabled() async =>
      (await getSystemSetting<bool>(
        'enable_server_speech',
        defaultValue: true,
      )) ??
      true;

  static Future<bool> isOfflineModeEnabled() async =>
      (await getSystemSetting<bool>(
        'enable_offline_mode',
        defaultValue: true,
      )) ??
      true;

  static Future<bool> isAnalyticsEnabled() async =>
      (await getSystemSetting<bool>(
        'enable_analytics',
        defaultValue: true,
      )) ??
      true;

  // ─────────────────── إحصاءات الاستخدام المحلية (Analytics) ───────────────────
  // نظام تتبع خفيف ومحلي بالكامل (بدون أي اتصال خارجي أو بيانات شخصية):
  // يُسجّل فقط عدّادات لأحداث استخدام مجهولة (مثال: "grade_synced_online": 42)
  // ويُفعَّل/يُعطَّل بالكامل عبر مفتاح "تفعيل التحليلات" في إعدادات النظام.
  static const String _analyticsBox = 'admin_analytics_box';

  static Future<void> _ensureAnalyticsBoxOpen() async {
    if (!Hive.isBoxOpen(_analyticsBox)) {
      await Hive.openBox(_analyticsBox);
    }
  }

  /// تسجيل حدث استخدام (عدّاد تراكمي) — لا يفعل شيئاً إذا كانت
  /// التحليلات معطّلة من إعدادات النظام. آمن تماماً عند الفشل.
  static Future<void> trackEvent(String eventName) async {
    try {
      if (!await isAnalyticsEnabled()) return;
      await _ensureAnalyticsBoxOpen();
      final box = Hive.box(_analyticsBox);
      final current = (box.get(eventName) as int?) ?? 0;
      await box.put(eventName, current + 1);
      await box.put('_last_updated', DateTime.now().toIso8601String());
    } catch (_) {
      // التتبع اختياري بالكامل ويجب ألا يوقف أي وظيفة أساسية عند الفشل
    }
  }

  /// جلب كل عدّادات الاستخدام المسجَّلة محلياً
  static Future<Map<String, int>> getAnalyticsCounters() async {
    await _ensureAnalyticsBoxOpen();
    final box = Hive.box(_analyticsBox);
    final result = <String, int>{};
    for (final key in box.keys) {
      if (key == '_last_updated') continue;
      final v = box.get(key);
      if (v is int) result[key.toString()] = v;
    }
    return result;
  }

  static Future<String?> getAnalyticsLastUpdated() async {
    await _ensureAnalyticsBoxOpen();
    return Hive.box(_analyticsBox).get('_last_updated') as String?;
  }

  static Future<void> clearAnalyticsCounters() async {
    await _ensureAnalyticsBoxOpen();
    await Hive.box(_analyticsBox).clear();
  }

  // ─────────────────── إحصاءات النظام ───────────────────

  static Future<Map<String, dynamic>> getSystemStats() async {
    await ensureOpen();
    final users = await getAllUsers();
    final activities = await getActivityLog();

    final byRole = <String, int>{};
    int activeCount = 0;
    int inactiveCount = 0;
    DateTime? lastActivity;

    for (final u in users) {
      byRole[u.role] = (byRole[u.role] ?? 0) + 1;
      if (u.isActive) {
        activeCount++;
      } else {
        inactiveCount++;
      }
    }

    if (activities.isNotEmpty) {
      try {
        lastActivity = DateTime.parse(activities.first['timestamp']);
      } catch (e, st) {
        ErrorHandler.logError(e, st, 'AdminService.parseLastActivity');
      }
    }

    // عدد المسجلين خلال آخر 7 أيام
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final newUsersWeek = users.where((u) {
      return u.createdAt != null && u.createdAt!.isAfter(weekAgo);
    }).length;

    return {
      'total_users': users.length,
      'active_users': activeCount,
      'inactive_users': inactiveCount,
      'developers': byRole[UserRole.developer] ?? 0,
      'admins': byRole[UserRole.admin] ?? 0,
      'managers': byRole[UserRole.manager] ?? 0,
      'teachers': byRole[UserRole.teacher] ?? 0,
      'total_activities': activities.length,
      'last_activity': lastActivity,
      'new_users_week': newUsersWeek,
    };
  }
}
