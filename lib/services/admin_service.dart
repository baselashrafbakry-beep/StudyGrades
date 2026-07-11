import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/subscription_model.dart';
import '../models/user_model.dart';
import '../utils/error_handler.dart';
import 'api_client.dart';
import 'secure_hive_service.dart';

/// خدمة إدارة المستخدمين والإعدادات الإدارية محلياً
/// تعمل في وضع Offline بشكل كامل وتُمكّن المطور والمدير من إدارة الحسابات
class AdminService {
  static const String _usersBox = 'admin_users_box';
  static const String _settingsBox = 'admin_settings_box';
  static const String _activityBox = 'admin_activity_box';
  static const String appName = 'StudyGrades';
  static const String appNameAr = 'نظام رصد الدرجات الصوتي';
  static const bool _allowOfflineAdminLogin = bool.fromEnvironment(
    'ALLOW_OFFLINE_ADMIN_LOGIN',
    defaultValue: false,
  );
  static const String _debugBootstrapPassword = String.fromEnvironment(
    'STUDYGRADES_DEBUG_BOOTSTRAP_PASSWORD',
    defaultValue: '',
  );
  static const String _passwordScheme = 'pbkdf2_sha256';
  static const int _passwordIterations = 120000;
  static const int _saltLength = 16;
  static const int _hashLength = 32;

  static bool get localAuthEnabled =>
      _allowOfflineAdminLogin ||
      (kDebugMode && _debugBootstrapPassword.isNotEmpty);

  /// إنشاء/فتح صناديق Hive
  static Future<void> ensureOpen() async {
    if (!Hive.isBoxOpen(_usersBox)) {
      await SecureHiveService.openBox(_usersBox);
    }
    if (!Hive.isBoxOpen(_settingsBox)) {
      await SecureHiveService.openBox(_settingsBox);
    }
    if (!Hive.isBoxOpen(_activityBox)) {
      await SecureHiveService.openBox(_activityBox);
    }
  }

  // ─────────────────── إدارة المستخدمين ───────────────────

  /// تهيئة الحساب الافتراضي للمطور (يتم استدعاؤها عند البدء)
  static Future<void> initDefaultDeveloper() async {
    await ensureOpen();
    final box = Hive.box(_usersBox);
    if (box.isEmpty &&
        _debugBootstrapPassword.isNotEmpty &&
        (kDebugMode || _allowOfflineAdminLogin)) {
      final developer = User(
        id: 1,
        username: 'basel',
        email: 'baselashraf.bakry@gmail.com',
        role: UserRole.developer,
        fullName: 'م/ باسل أشرف',
        phone: '',
        isActive: true,
        createdAt: DateTime.now(),
        subscription: Subscription.developerLifetime(),
      );
      await _saveUserDirect(developer, password: _debugBootstrapPassword);
      await logActivity('تهيئة', 'تم إنشاء حساب المطور الافتراضي');
    }
  }

  /// حفظ مستخدم مع كلمة مرور مخزنة كـ PBKDF2-SHA256.
  static Future<void> _saveUserDirect(User user, {String? password}) async {
    final box = Hive.box(_usersBox);
    final data = user.toJson();
    if (password != null) {
      data['password_hash'] = _hashPassword(password);
    } else {
      // إن لم تُمرر كلمة مرور، احتفظ بالقديمة إن وُجدت
      final existing = box.get(user.id.toString());
      if (existing != null) {
        final prev = jsonDecode(existing as String) as Map<String, dynamic>;
        data['password_hash'] = prev['password_hash'];
      }
    }
    await box.put(user.id.toString(), jsonEncode(data));
  }

  /// جلب جميع المستخدمين
  static Future<List<User>> getAllUsers() async {
    if (!localAuthEnabled) {
      final users = await apiClient.adminListUsers();
      users.sort((a, b) => UserRole.level(b.role) - UserRole.level(a.role));
      return users;
    }
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
    Subscription? subscription,
    User? actor,
  }) async {
    _assertCanAssignRole(actor, role);
    if (!localAuthEnabled) {
      return apiClient.adminCreateUser(
        username: username,
        password: password,
        email: email,
        role: role,
        fullName: fullName,
        phone: phone,
        subscription: subscription,
      );
    }
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

    final newId = users.isEmpty
        ? 2
        : (users.map((u) => u.id).reduce((a, b) => a > b ? a : b) + 1);

    final user = User(
      id: newId,
      username: username,
      email: email,
      role: role,
      fullName: fullName,
      phone: phone,
      isActive: true,
      createdAt: DateTime.now(),
      subscription: subscription,
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
    User? actor,
  }) async {
    final existing = await getUserById(user.id);
    _assertCanModifyUser(actor, existing);
    _assertCanAssignRole(actor, user.role);
    if (!localAuthEnabled) {
      return apiClient.adminUpdateUser(user, newPassword: newPassword);
    }
    await ensureOpen();
    await _saveUserDirect(user, password: newPassword);
    await logActivity('تعديل حساب', 'تم تعديل بيانات: ${user.username}');
    return user;
  }

  static void _assertCanAssignRole(User? actor, String role) {
    if (!UserRole.all.contains(role)) {
      throw Exception('دور المستخدم غير صالح');
    }
    if (actor == null || !actor.canManageUsers) {
      throw Exception('لا تملك صلاحية إدارة المستخدمين');
    }
    if (UserRole.level(role) >= UserRole.level(actor.role)) {
      throw Exception('لا يمكنك منح دور يساوي صلاحيتك أو يتجاوزها');
    }
  }

  static void _assertCanModifyUser(User? actor, User? target) {
    if (actor == null || !actor.canManageUsers) {
      throw Exception('لا تملك صلاحية إدارة المستخدمين');
    }
    if (target == null) {
      throw Exception('المستخدم غير موجود');
    }
    if (!actor.canModifyUser(target)) {
      throw Exception('لا تملك صلاحية تعديل هذا المستخدم');
    }
  }

  /// حذف مستخدم
  static Future<void> deleteUser(int userId, {User? actor}) async {
    final user = await getUserById(userId);
    _assertCanModifyUser(actor, user);
    if (user?.role == UserRole.developer || user?.username == 'developer') {
      throw Exception('لا يمكن حذف حساب المطور');
    }
    if (!localAuthEnabled) {
      await apiClient.adminDeactivateUser(userId);
      return;
    }
    await ensureOpen();
    final box = Hive.box(_usersBox);
    await box.delete(userId.toString());
    if (user != null) {
      await logActivity('حذف حساب', 'تم حذف الحساب: ${user.username}');
    }
  }

  /// تفعيل/تعطيل حساب
  static Future<void> toggleUserActive(int userId, {User? actor}) async {
    final user = await getUserById(userId);
    _assertCanModifyUser(actor, user);
    final target = user!;
    final updated = target.copyWith(isActive: !target.isActive);
    if (!localAuthEnabled) {
      await apiClient.adminUpdateUser(updated);
      return;
    }
    await _saveUserDirect(updated);
    await logActivity(
      updated.isActive ? 'تفعيل' : 'تجميد',
      '${updated.isActive ? 'تم تفعيل' : 'تم تجميد'} حساب: ${updated.username}',
    );
  }

  /// إعادة تعيين كلمة المرور
  static Future<void> resetPassword(
    int userId,
    String newPassword, {
    User? actor,
  }) async {
    final user = await getUserById(userId);
    _assertCanModifyUser(actor, user);
    if (!localAuthEnabled) {
      await apiClient.adminUpdateUser(user!, newPassword: newPassword);
      return;
    }
    await _saveUserDirect(user!, password: newPassword);
    await logActivity(
      'تغيير كلمة المرور',
      'تم تغيير كلمة المرور لـ: ${user.username}',
    );
  }

  /// جلب مستخدم بواسطة ID
  static Future<User?> getUserById(int userId) async {
    if (!localAuthEnabled) {
      final users = await apiClient.adminListUsers();
      for (final user in users) {
        if (user.id == userId) return user;
      }
      return null;
    }
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

  /// التحقق من بيانات تسجيل الدخول محلياً (للاستخدام كـ fallback).
  /// كلمات المرور الجديدة تحفظ كـ PBKDF2-SHA256 مع salt عشوائي، مع مسار
  /// ترحيل فقط للتثبيتات المحلية القديمة التي كانت تستخدم Base64.
  static Future<User?> verifyCredentials(
    String username,
    String password,
  ) async {
    if (!localAuthEnabled) return null;
    await initDefaultDeveloper();
    final box = Hive.box(_usersBox);
    for (final key in box.keys) {
      try {
        final raw = box.get(key);
        if (raw == null) continue;
        final data = jsonDecode(raw as String) as Map<String, dynamic>;
        final dbUsername = (data['username'] ?? '').toString().toLowerCase();
        if (dbUsername != username.toLowerCase()) continue;

        final dbHash = data['password_hash']?.toString() ?? '';
        if (_verifyPassword(password, dbHash)) {
          if (!dbHash.startsWith('$_passwordScheme:')) {
            data['password_hash'] = _hashPassword(password);
            await box.put(key, jsonEncode(data));
          }
          // فحص الحالة أولاً قبل تحديث آخر دخول
          final user = User.fromJson(data);
          if (!user.isActive) {
            throw Exception('هذا الحساب موقوف. تواصل مع المدير.');
          }
          // تحديث آخر دخول
          final updated = user.copyWith(lastLogin: DateTime.now());
          await _saveUserDirect(updated);
          return updated;
        }
      } catch (e) {
        if (e.toString().contains('موقوف')) rethrow;
        // تجاهل أخطاء JSON parsing للمفاتيح الأخرى
      }
    }
    return null;
  }

  static String _hashPassword(String password) {
    final random = Random.secure();
    final salt = List<int>.generate(_saltLength, (_) => random.nextInt(256));
    final hash = _pbkdf2(
      utf8.encode(password),
      salt,
      _passwordIterations,
      _hashLength,
    );
    return [
      _passwordScheme,
      _passwordIterations,
      base64UrlEncode(salt),
      base64UrlEncode(hash),
    ].join(':');
  }

  static bool _verifyPassword(String password, String stored) {
    if (stored.startsWith('$_passwordScheme:')) {
      final parts = stored.split(':');
      if (parts.length != 4) return false;
      final iterations = int.tryParse(parts[1]);
      if (iterations == null || iterations < 100000) return false;
      try {
        final salt = base64Url.decode(parts[2]);
        final expected = base64Url.decode(parts[3]);
        final actual = _pbkdf2(
          utf8.encode(password),
          salt,
          iterations,
          expected.length,
        );
        return _constantTimeEquals(actual, expected);
      } catch (_) {
        return false;
      }
    }

    // Legacy migration path for older local installs that used Base64.
    final legacy = base64Encode(utf8.encode(password));
    return _constantTimeEquals(utf8.encode(legacy), utf8.encode(stored));
  }

  static List<int> _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int length,
  ) {
    final hmac = Hmac(sha256, password);
    final blocks = (length / sha256.convert(const []).bytes.length).ceil();
    final output = <int>[];

    for (var blockIndex = 1; blockIndex <= blocks; blockIndex++) {
      final block = Uint8List(salt.length + 4);
      block.setAll(0, salt);
      ByteData.view(
        block.buffer,
      ).setUint32(salt.length, blockIndex, Endian.big);

      var u = hmac.convert(block).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      output.addAll(t);
    }

    return output.take(length).toList(growable: false);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    final max = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < max; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      diff |= av ^ bv;
    }
    return diff == 0;
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
    entries.sort(
      (a, b) => (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''),
    );
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

  // ─────────────────── إحصاءات النظام ───────────────────

  static Future<Map<String, dynamic>> getSystemStats() async {
    await ensureOpen();
    final users = await getAllUsers();
    final activities = await getActivityLog();

    final byRole = <String, int>{};
    int activeCount = 0;
    int inactiveCount = 0;
    int activeSubscriptions = 0;
    int expiredSubscriptions = 0;
    int trialSubscriptions = 0;
    DateTime? lastActivity;

    for (final u in users) {
      byRole[u.role] = (byRole[u.role] ?? 0) + 1;
      if (u.isActive) {
        activeCount++;
      } else {
        inactiveCount++;
      }
      if (u.subscription.isUsable) {
        activeSubscriptions++;
      } else {
        expiredSubscriptions++;
      }
      if (u.subscription.status == SubscriptionStatus.trialing) {
        trialSubscriptions++;
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
      'active_subscriptions': activeSubscriptions,
      'expired_subscriptions': expiredSubscriptions,
      'trial_subscriptions': trialSubscriptions,
      'total_activities': activities.length,
      'last_activity': lastActivity,
      'new_users_week': newUsersWeek,
    };
  }
}
