import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import '../models/user_model.dart';
import '../utils/error_handler.dart';
import 'hive_encryption_service.dart';
import 'subscription_service.dart';

/// خدمة إدارة المستخدمين والإعدادات الإدارية محلياً
/// تعمل في وضع Offline بشكل كامل وتُمكّن المطور والمدير من إدارة الحسابات
class AdminService {
  static const String _usersBox = 'admin_users_box';
  static const String _settingsBox = 'admin_settings_box';
  static const String _activityBox = 'admin_activity_box';

  /// إنشاء/فتح صناديق Hive — 🔐 عبر HiveEncryptionService لتطبيق تشفير
  /// AES-256 (Android/iOS) مع ترحيل آمن لأي بيانات قديمة غير مشفَّرة.
  /// راجع main.dart._initStorage() للنقطة الأساسية لفتح هذه الصناديق؛
  /// هذا التابع هو مجرد شبكة أمان (isBoxOpen يمنع إعادة الفتح المزدوج).
  static Future<void> ensureOpen() async {
    if (!Hive.isBoxOpen(_usersBox)) {
      await HiveEncryptionService.openEncryptedBox(_usersBox);
    }
    if (!Hive.isBoxOpen(_settingsBox)) {
      await HiveEncryptionService.openEncryptedBox(_settingsBox);
    }
    if (!Hive.isBoxOpen(_activityBox)) {
      await HiveEncryptionService.openEncryptedBox(_activityBox);
    }
  }

  // ─────────────────── إدارة المستخدمين ───────────────────

  // ═══════════════════════════════════════════════════════
  // بيانات المطور الرسمية — م. باسل أشرف
  // ═══════════════════════════════════════════════════════
  static const String developerName = 'م. باسل أشرف';
  static const String developerUsername = 'basel';
  static const String developerEmail = 'baselashraf.bakry@gmail.com';
  static const String developerPhone = '01014543845';
  static const String developerWhatsApp = 'https://wa.me/201014543845';
  static const String appVersion = '2.0.0';
  // ⚠️ محدَّث بأمر صريح من صاحب المنتج ليطابق APP_DISPLAY_NAME و
  // ANDROID_APPLICATION_ID الرسميين في ملف الإعداد التجاري
  // (StudyGrades-commercial.env).
  static const String appName = 'StudyGrades';
  static const String appNameAr = 'نظام رصد الدرجات الصوتي';
  static const String copyrightYear = '2026';
  static const String packageName = 'com.studygrades.app';
  static const String serverUrl = 'studygrades2026.pythonanywhere.com';
  static const String serverUrlFull =
      'https://studygrades2026.pythonanywhere.com';

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
      // 🔴 ثغرة أمنية تم اكتشافها وإصلاحها هنا (Hardcoded Default Password):
      // كلمة مرور المطوّر الافتراضية 'Basel@2026' مكتوبة في الكود المصدري،
      // وقابلة نظرياً للاستخلاص من ملف APK المُفكَّك. المشكلة الأخطر
      // المكتشَفة أثناء المراجعة: دالة resetPassword() كانت تمنع صراحةً
      // المستخدم من تغيير كلمة مروره الخاصة (actorId == userId) وتُحيله
      // إلى "شاشة الملف الشخصي" — وهي شاشة غير موجودة إطلاقاً في التطبيق!
      // بمعنى أن حساب المطوّر لم يكن يملك أي وسيلة فعلية لتغيير كلمة
      // مروره الافتراضية عبر الواجهة. الإصلاح: تمت إضافة آلية كاملة
      // للتغيير الذاتي (changeOwnPassword) + علم "يجب تغيير كلمة المرور"
      // (mustChangePassword) يُفعَّل هنا تلقائياً ليُجبر المطوّر على تعيين
      // كلمة مرور جديدة فور أول تسجيل دخول (راجع login_screen.dart).
      await _saveUserDirect(developer, password: 'Basel@2026');
      await _setMustChangePassword(developer.id, true);
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
  ///
  /// ملاحظة: حقل `must_change_password` (علم "يجب تغيير كلمة المرور")
  /// يُحفَظ خارج نموذج User.toJson() العادي، لذا يجب الحفاظ عليه صراحةً
  /// من البيانات الموجودة مسبقاً في كل مرة يُستدعى فيها هذا التابع، وإلا
  /// سيُفقَد العلم عند أي تعديل آخر على المستخدم (تفعيل/تعطيل/تعديل بيانات).
  static Future<void> _saveUserDirect(
    User user, {
    String? password,
    bool? mustChangePassword,
  }) async {
    final box = Hive.box(_usersBox);
    final data = user.toJson();
    final existingRaw = box.get(user.id.toString());
    Map<String, dynamic>? existing;
    if (existingRaw != null) {
      try {
        existing = jsonDecode(existingRaw as String) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (password != null) {
      final salt = _generateSalt();
      data['password_salt'] = salt;
      data['password_hash'] = _hashPassword(password, salt);
    } else if (existing != null) {
      // إن لم تُمرر كلمة مرور، احتفظ بالقديمة إن وُجدت (hash + salt)
      data['password_hash'] = existing['password_hash'];
      data['password_salt'] = existing['password_salt'];
    }

    // الحفاظ على علم "يجب تغيير كلمة المرور" ما لم يُطلب تغييره صراحةً
    if (mustChangePassword != null) {
      data['must_change_password'] = mustChangePassword;
    } else if (existing != null && existing['must_change_password'] != null) {
      data['must_change_password'] = existing['must_change_password'];
    }

    await box.put(user.id.toString(), jsonEncode(data));
  }

  /// تفعيل/إلغاء علم "يجب تغيير كلمة المرور" لمستخدم معيّن دون التأثير
  /// على أي بيانات أخرى للمستخدم.
  static Future<void> _setMustChangePassword(int userId, bool value) async {
    final box = Hive.box(_usersBox);
    final raw = box.get(userId.toString());
    if (raw == null) return;
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      data['must_change_password'] = value;
      await box.put(userId.toString(), jsonEncode(data));
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'AdminService._setMustChangePassword');
    }
  }

  /// هل يجب على هذا المستخدم تغيير كلمة مروره قبل المتابعة؟
  /// (يُستخدَم لإجبار المطوّر على تغيير كلمة المرور الافتراضية عند أول دخول)
  static Future<bool> getMustChangePassword(int userId) async {
    await ensureOpen();
    final box = Hive.box(_usersBox);
    final raw = box.get(userId.toString());
    if (raw == null) return false;
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      return data['must_change_password'] == true;
    } catch (_) {
      return false;
    }
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

  // ═══════════════════════════════════════════════════════
  // فرض الصلاحيات على مستوى الخدمة (Defense in Depth)
  // ═══════════════════════════════════════════════════════
  // ⚠️ ملاحظة أمنية هامة: قبل هذا التحديث كانت دوال إدارة المستخدمين
  // (createUser/updateUser/deleteUser/toggleUserActive/resetPassword)
  // تُنفَّذ دون أي تحقق من صلاحية الطرف المستدعي (Caller) على مستوى
  // الخدمة نفسها — الاعتماد كان بالكامل على أن واجهة المستخدم
  // (users_management_screen.dart) تُخفي الأزرار عبر `canModifyUser()`.
  // هذا يعني أن أي مسار برمجي آخر يستدعي هذه الدوال مباشرة (حالياً أو
  // مستقبلاً) كان يمكنه تجاوز التحقق تماماً، بما في ذلك احتمال إنشاء/
  // ترقية حساب لرتبة "مطوّر" من واجهة إدارة المستخدمين نفسها (كانت
  // القائمة المنسدلة للأدوار تعرض كل الأدوار دون قيد). الآن كل دالة
  // تفرض التحقق من الهرمية إلزامياً بغضّ النظر عن استدعاء الواجهة.

  /// يتحقق أن الدور المرسِل (actorRole) يملك أصلاً صلاحية إدارة
  /// المستخدمين (مطوّر أو مدير فقط) — مطابق لـ User.canManageUsers.
  static void _ensureCanManageUsers(String actorRole) {
    if (UserRole.level(actorRole) < UserRole.level(UserRole.admin)) {
      throw Exception('لا تملك صلاحية إدارة المستخدمين');
    }
  }

  /// يتحقق أن actorRole يفوق targetRole في التسلسل الهرمي، أي لا يمكن
  /// لمستخدم إنشاء/تعديل/حذف/تجميد حساب بنفس رتبته أو أعلى منها
  /// (مطابق لـ User.canModifyUser، لكن مُطبَّق قسرياً هنا على الخدمة).
  static void _ensureOutranks(String actorRole, String targetRole) {
    if (UserRole.level(actorRole) <= UserRole.level(targetRole)) {
      throw Exception('لا تملك صلاحية كافية لتنفيذ هذا الإجراء على هذا الحساب');
    }
  }

  /// إنشاء مستخدم جديد
  static Future<User> createUser({
    required String username,
    required String password,
    required String email,
    required String role,
    required String actorRole,
    String fullName = '',
    String? phone,
  }) async {
    await ensureOpen();
    _ensureCanManageUsers(actorRole);
    // لا يمكن إنشاء حساب برتبة مساوية أو أعلى من رتبة المُنشِئ نفسه
    // (يمنع مثلاً مديراً من إنشاء حساب "مطوّر" أو "مدير" آخر بصلاحياته).
    _ensureOutranks(actorRole, role);

    final users = await getAllUsers();

    // التحقق من عدم تكرار اسم المستخدم
    if (users.any((u) => u.username.toLowerCase() == username.toLowerCase())) {
      throw Exception('اسم المستخدم موجود بالفعل');
    }
    if (email.isNotEmpty &&
        users.any((u) => u.email.toLowerCase() == email.toLowerCase())) {
      throw Exception('البريد الإلكتروني مستخدم بالفعل');
    }

    // 🔴 فرض حد "عدد المعلمين" (Seat Limits) بحسب باقة الاشتراك الحالية —
    // انظر التوثيق الكامل أعلى SubscriptionService.getMaxTeachers().
    // نحتسب فقط الحسابات النشطة (isActive) ذات دور "معلم" تحديداً —
    // حسابات المطوّر/المدير/المشرف لا تُستهلَك منها أي "مقعد".
    if (role == UserRole.teacher) {
      final maxTeachers = await SubscriptionService.getMaxTeachers();
      if (maxTeachers != -1) {
        final activeTeachersCount =
            users.where((u) => u.role == UserRole.teacher && u.isActive).length;
        if (activeTeachersCount >= maxTeachers) {
          throw Exception(
              'وصلت للحد الأقصى لعدد حسابات المعلمين ($maxTeachers) '
              'في باقة اشتراكك الحالية.\nقم بترقية الباقة لإضافة معلمين آخرين، '
              'أو جمّد/احذف حساب معلم غير مستخدَم أولاً.');
        }
      }
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
    required int actorId,
    required String actorRole,
  }) async {
    await ensureOpen();
    _ensureCanManageUsers(actorRole);
    if (actorId == user.id) {
      throw Exception('لا يمكنك تعديل حسابك الخاص من هذه الشاشة');
    }
    final existing = await getUserById(user.id);
    if (existing == null) {
      throw Exception('المستخدم غير موجود');
    }
    // يجب أن يفوق المُعدِّل رتبة الحساب الحالية للمستهدف...
    _ensureOutranks(actorRole, existing.role);
    // ...ويجب أن يفوق أيضاً الرتبة الجديدة المطلوب تعيينها (يمنع تصعيد
    // الصلاحيات عبر تغيير دور المستخدم إلى رتبة مساوية/أعلى من المُعدِّل).
    _ensureOutranks(actorRole, user.role);

    await _saveUserDirect(user, password: newPassword);
    await logActivity(
      'تعديل حساب',
      'تم تعديل بيانات: ${user.username}',
    );
    return user;
  }

  /// حذف مستخدم
  static Future<void> deleteUser(
    int userId, {
    required int actorId,
    required String actorRole,
  }) async {
    await ensureOpen();
    _ensureCanManageUsers(actorRole);
    if (actorId == userId) {
      throw Exception('لا يمكنك حذف حسابك الخاص');
    }
    final user = await getUserById(userId);
    if (user == null) return;
    // حماية صريحة على مستوى الخدمة لحساب المطوّر (بالإضافة للحماية
    // الطبيعية عبر الهرمية، لأن مستوى "مطوّر" هو الأعلى ولا يمكن لأي
    // طرف آخر تجاوزه أصلاً، لكن هذا تحقق صريح إضافي دفاعاً في العمق).
    if (user.role == UserRole.developer || user.username == developerUsername) {
      throw Exception('لا يمكن حذف حساب المطوّر — محمي من الحذف');
    }
    _ensureOutranks(actorRole, user.role);

    final box = Hive.box(_usersBox);
    await box.delete(userId.toString());
    await logActivity(
      'حذف حساب',
      'تم حذف الحساب: ${user.username}',
    );
  }

  /// تفعيل/تعطيل حساب
  static Future<void> toggleUserActive(
    int userId, {
    required int actorId,
    required String actorRole,
  }) async {
    await ensureOpen();
    _ensureCanManageUsers(actorRole);
    if (actorId == userId) {
      throw Exception('لا يمكنك تجميد/تفعيل حسابك الخاص');
    }
    final user = await getUserById(userId);
    if (user == null) return;
    _ensureOutranks(actorRole, user.role);

    final willActivate = !user.isActive;

    // 🔴 نفس فرض حد "عدد المعلمين" يجب أن يُطبَّق أيضاً عند *إعادة تفعيل*
    // حساب معلم مجمَّد سابقاً — وإلا فإن حداً يمنع "الإنشاء" لكنه لا يمنع
    // "إعادة التفعيل" يبقى قابلاً للالتفاف حوله بسهولة (جمّد حساباً قديماً
    // ثم أعد تفعيله بلا حدود بدل إنشاء حساب جديد).
    if (willActivate && user.role == UserRole.teacher) {
      final maxTeachers = await SubscriptionService.getMaxTeachers();
      if (maxTeachers != -1) {
        final users = await getAllUsers();
        final activeTeachersCount = users
            .where((u) =>
                u.role == UserRole.teacher && u.isActive && u.id != user.id)
            .length;
        if (activeTeachersCount >= maxTeachers) {
          throw Exception(
              'وصلت للحد الأقصى لعدد حسابات المعلمين ($maxTeachers) '
              'في باقة اشتراكك الحالية.\nقم بترقية الباقة لإعادة تفعيل هذا الحساب.');
        }
      }
    }

    final updated = user.copyWith(isActive: willActivate);
    await _saveUserDirect(updated);
    await logActivity(
      updated.isActive ? 'تفعيل' : 'تجميد',
      '${updated.isActive ? 'تم تفعيل' : 'تم تجميد'} حساب: ${updated.username}',
    );
  }

  /// إعادة تعيين كلمة مرور مستخدم *آخر* (إجراء إداري، لا يتطلب معرفة
  /// كلمة المرور الحالية للمستهدف — يُستخدَم من "إدارة المستخدمين").
  ///
  /// لتغيير المستخدم لكلمة مروره *الخاصة* استخدم [changeOwnPassword] بدلاً
  /// من هذا التابع (يتطلب التحقق من كلمة المرور الحالية أولاً).
  static Future<void> resetPassword(
    int userId,
    String newPassword, {
    required int actorId,
    required String actorRole,
  }) async {
    await ensureOpen();
    _ensureCanManageUsers(actorRole);
    if (actorId == userId) {
      throw Exception(
          'لتغيير كلمة مرورك الخاصة استخدم "الإعدادات" ← "تغيير كلمة المرور"');
    }
    final user = await getUserById(userId);
    if (user == null) return;
    _ensureOutranks(actorRole, user.role);

    await _saveUserDirect(user,
        password: newPassword, mustChangePassword: false);
    await logActivity(
      'تغيير كلمة المرور',
      'تم تغيير كلمة المرور لـ: ${user.username}',
    );
  }

  // ═══════════════════════════════════════════════════════
  // 🔐 التغيير الذاتي لكلمة المرور (Self-Service Password Change)
  // ═══════════════════════════════════════════════════════
  // أُضيف هذا التابع لسدّ ثغرة/عطل مكتشَف: resetPassword() كانت تمنع
  // المستخدم من تغيير كلمة مروره الخاصة وتُحيله إلى "شاشة ملف شخصي"
  // غير موجودة في التطبيق. هذا التابع يوفر المسار البديل الصحيح، مع
  // اشتراط أمني إضافي (لا يتوفر في resetPassword الإداري): يجب إثبات
  // معرفة كلمة المرور *الحالية* قبل قبول كلمة المرور الجديدة، تماماً
  // كما هو معمول به في كل تطبيقات "تغيير كلمة المرور الذاتي" الاحترافية.
  static Future<void> changeOwnPassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    await ensureOpen();
    if (newPassword.length < 6) {
      throw Exception('كلمة المرور الجديدة يجب ألا تقل عن 6 أحرف');
    }
    final box = Hive.box(_usersBox);
    final raw = box.get(userId.toString());
    if (raw == null) {
      throw Exception('المستخدم غير موجود');
    }
    final data = jsonDecode(raw as String) as Map<String, dynamic>;
    final user = User.fromJson(data);

    // التحقق من كلمة المرور الحالية (يدعم الصيغة الجديدة SHA-256+Salt
    // والصيغة القديمة base64 معاً، مطابقاً لمنطق verifyCredentials).
    final dbHash = data['password_hash']?.toString() ?? '';
    final dbSalt = data['password_salt']?.toString();
    bool matched;
    if (dbSalt != null && dbSalt.isNotEmpty) {
      matched = _hashPassword(currentPassword, dbSalt) == dbHash;
    } else {
      matched = dbHash == base64Encode(utf8.encode(currentPassword));
    }
    if (!matched) {
      throw Exception('كلمة المرور الحالية غير صحيحة');
    }
    if (currentPassword == newPassword) {
      throw Exception('كلمة المرور الجديدة يجب أن تختلف عن الحالية');
    }

    await _saveUserDirect(user,
        password: newPassword, mustChangePassword: false);
    await logActivity(
      'تغيير كلمة المرور',
      'قام ${user.username} بتغيير كلمة مروره الخاصة',
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
    entries
        .sort((a, b) => (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));
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
      // 🔐 نفس تشفير AES-256 المطبَّق على باقي صناديق الأدمن — أُضيف
      // هذا الصندوق أيضاً إلى القائمة المركزية في main.dart._initStorage()
      // ليُفتَح مشفَّراً منذ بدء التشغيل؛ هذا الاستدعاء هنا شبكة أمان فقط.
      await HiveEncryptionService.openEncryptedBox(_analyticsBox);
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
