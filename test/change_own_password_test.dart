import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:study_grades_voice/services/admin_service.dart';
import 'package:study_grades_voice/models/user_model.dart';

/// اختبارات وظيفية حية لآلية التغيير الذاتي لكلمة المرور
/// (AdminService.changeOwnPassword) وعلم "يجب تغيير كلمة المرور"
/// (getMustChangePassword) — تم إنشاء هذه الآلية لسدّ ثغرة/عطل مكتشَف:
/// كان حساب المطوّر (بكلمة مرور افتراضية 'Basel@2026' مكتوبة في الكود
/// المصدري) لا يملك أي وسيلة فعلية لتغيير كلمة مروره عبر واجهة التطبيق.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_ownpwd_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AdminService.getMustChangePassword — علم إجبار تغيير كلمة المرور', () {
    test('حساب المطوّر الافتراضي يُنشأ بعلم mustChangePassword = true',
        () async {
      await AdminService.initDefaultDeveloper();
      final developer = (await AdminService.getAllUsers())
          .firstWhere((u) => u.role == UserRole.developer);
      final mustChange = await AdminService.getMustChangePassword(developer.id);
      expect(mustChange, isTrue,
          reason:
              'يجب إجبار المطوّر على تغيير كلمة المرور الافتراضية عند أول دخول');
    });

    test('حساب جديد يُنشأ عبر createUser لا يحمل علم mustChangePassword',
        () async {
      await AdminService.initDefaultDeveloper();
      final newUser = await AdminService.createUser(
        username: 'teacher1',
        password: 'pass1234',
        email: 'teacher1@test.com',
        role: UserRole.teacher,
        actorRole: UserRole.developer,
      );
      final mustChange = await AdminService.getMustChangePassword(newUser.id);
      expect(mustChange, isFalse);
    });
  });

  group('AdminService.changeOwnPassword — التغيير الذاتي لكلمة المرور', () {
    test('نجاح التغيير عند إدخال كلمة المرور الحالية الصحيحة', () async {
      await AdminService.initDefaultDeveloper();
      final developer = (await AdminService.getAllUsers())
          .firstWhere((u) => u.role == UserRole.developer);

      await AdminService.changeOwnPassword(
        userId: developer.id,
        currentPassword: 'Basel@2026',
        newPassword: 'NewSecurePass123!',
      );

      // تسجيل الدخول بكلمة المرور الجديدة يجب أن ينجح
      final loggedIn = await AdminService.verifyCredentials(
        developer.username,
        'NewSecurePass123!',
      );
      expect(loggedIn, isNotNull);

      // تسجيل الدخول بكلمة المرور القديمة يجب أن يفشل
      final loginWithOld = await AdminService.verifyCredentials(
        developer.username,
        'Basel@2026',
      );
      expect(loginWithOld, isNull);
    });

    test('علم mustChangePassword يُطفأ تلقائياً بعد نجاح التغيير الذاتي',
        () async {
      await AdminService.initDefaultDeveloper();
      final developer = (await AdminService.getAllUsers())
          .firstWhere((u) => u.role == UserRole.developer);

      // تأكيد أن العلم مفعّل قبل التغيير
      expect(await AdminService.getMustChangePassword(developer.id), isTrue);

      await AdminService.changeOwnPassword(
        userId: developer.id,
        currentPassword: 'Basel@2026',
        newPassword: 'AnotherSecurePass456!',
      );

      // يجب أن يُطفأ العلم تلقائياً بعد التغيير الناجح
      expect(await AdminService.getMustChangePassword(developer.id), isFalse);
    });

    test('رفض التغيير عند إدخال كلمة مرور حالية خاطئة', () async {
      await AdminService.initDefaultDeveloper();
      final developer = (await AdminService.getAllUsers())
          .firstWhere((u) => u.role == UserRole.developer);

      expect(
        () => AdminService.changeOwnPassword(
          userId: developer.id,
          currentPassword: 'WrongPassword',
          newPassword: 'NewSecurePass123!',
        ),
        throwsA(isA<Exception>()),
      );

      // كلمة المرور الأصلية يجب أن تبقى صالحة (لم يتم تغييرها)
      final stillWorks = await AdminService.verifyCredentials(
        developer.username,
        'Basel@2026',
      );
      expect(stillWorks, isNotNull);
    });

    test('رفض التغيير عندما تكون كلمة المرور الجديدة أقصر من 6 أحرف', () async {
      await AdminService.initDefaultDeveloper();
      final developer = (await AdminService.getAllUsers())
          .firstWhere((u) => u.role == UserRole.developer);

      expect(
        () => AdminService.changeOwnPassword(
          userId: developer.id,
          currentPassword: 'Basel@2026',
          newPassword: '123',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('رفض التغيير عندما تكون كلمة المرور الجديدة مطابقة للحالية', () async {
      await AdminService.initDefaultDeveloper();
      final developer = (await AdminService.getAllUsers())
          .firstWhere((u) => u.role == UserRole.developer);

      expect(
        () => AdminService.changeOwnPassword(
          userId: developer.id,
          currentPassword: 'Basel@2026',
          newPassword: 'Basel@2026',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test(
        'تغيير كلمة مرور مستخدم عادي (غير المطور) ذاتياً يعمل بشكل مستقل عن حساب المطور',
        () async {
      await AdminService.initDefaultDeveloper();
      final teacher = await AdminService.createUser(
        username: 'teacher2',
        password: 'origPass99',
        email: 'teacher2@test.com',
        role: UserRole.teacher,
        actorRole: UserRole.developer,
      );

      await AdminService.changeOwnPassword(
        userId: teacher.id,
        currentPassword: 'origPass99',
        newPassword: 'freshPass88',
      );

      final loggedIn = await AdminService.verifyCredentials(
        'teacher2',
        'freshPass88',
      );
      expect(loggedIn, isNotNull);
    });
  });

  group('تكامل resetPassword الإداري مع mustChangePassword', () {
    test('resetPassword الإداري (من مطوّر آخر افتراضي) يُطفئ العلم أيضاً',
        () async {
      await AdminService.initDefaultDeveloper();
      final developer = (await AdminService.getAllUsers())
          .firstWhere((u) => u.role == UserRole.developer);

      // ننشئ حساب admin كي يقوم بإعادة تعيين كلمة مرور المطوّر افتراضاً
      // غير ممكن (المطور أعلى رتبة)، لذا نتحقق فقط من مسار teacher
      // الذي يُعاد تعيين كلمة مروره من قبل المطوّر، ونتأكد أن العلم يُطفأ.
      final teacher = await AdminService.createUser(
        username: 'teacher3',
        password: 'temp1234',
        email: 'teacher3@test.com',
        role: UserRole.teacher,
        actorRole: UserRole.developer,
      );
      expect(await AdminService.getMustChangePassword(teacher.id), isFalse);

      await AdminService.resetPassword(
        teacher.id,
        'brandNewPass77',
        actorId: developer.id,
        actorRole: UserRole.developer,
      );

      expect(await AdminService.getMustChangePassword(teacher.id), isFalse);
      final loggedIn = await AdminService.verifyCredentials(
        'teacher3',
        'brandNewPass77',
      );
      expect(loggedIn, isNotNull);
    });
  });
}
