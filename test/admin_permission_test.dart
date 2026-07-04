import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:study_grades_voice/services/admin_service.dart';
import 'package:study_grades_voice/models/user_model.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_perm_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AdminService — فرض الصلاحيات على مستوى الخدمة (Defense in Depth)', () {
    test('مدير (admin) لا يستطيع إنشاء حساب برتبة admin أو developer',
        () async {
      await AdminService.initDefaultDeveloper();
      // إنشاء حساب admin بواسطة المطور نفسه
      final adminUser = await AdminService.createUser(
        username: 'test_admin',
        password: 'pass1234',
        email: 'admin@test.com',
        role: UserRole.admin,
        actorRole: UserRole.developer,
      );
      expect(adminUser.role, UserRole.admin);

      // الآن نحاول أن ينشئ هذا الـ admin حساب admin آخر -> يجب أن يُرفض
      expect(
        () => AdminService.createUser(
          username: 'test_admin2',
          password: 'pass1234',
          email: 'admin2@test.com',
          role: UserRole.admin,
          actorRole: UserRole.admin,
        ),
        throwsA(isA<Exception>()),
      );

      // ومحاولة إنشاء حساب developer من قبل admin -> يجب أن يُرفض أيضاً
      expect(
        () => AdminService.createUser(
          username: 'fake_dev',
          password: 'pass1234',
          email: 'fakedev@test.com',
          role: UserRole.developer,
          actorRole: UserRole.admin,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('teacher لا يستطيع استدعاء أي دالة إدارة مستخدمين إطلاقاً', () async {
      await AdminService.initDefaultDeveloper();
      expect(
        () => AdminService.createUser(
          username: 'x',
          password: 'pass1234',
          email: 'x@test.com',
          role: UserRole.teacher,
          actorRole: UserRole.teacher,
        ),
        throwsA(isA<Exception>()),
      );

      expect(
        () => AdminService.deleteUser(1,
            actorId: 99, actorRole: UserRole.teacher),
        throwsA(isA<Exception>()),
      );
    });

    test('لا يمكن حذف حساب المطوّر حتى من قبل مطوّر آخر (نظرياً)', () async {
      await AdminService.initDefaultDeveloper();
      // محاولة حذف حساب المطور (id=1) بواسطة "مطور" آخر وهمي actorId مختلف
      expect(
        () => AdminService.deleteUser(1,
            actorId: 999, actorRole: UserRole.developer),
        throwsA(isA<Exception>()),
      );
    });

    test('لا يمكن للمستخدم تعديل/حذف/تجميد حسابه الخاص عبر actorId==targetId',
        () async {
      await AdminService.initDefaultDeveloper();
      final admin = await AdminService.createUser(
        username: 'selfadmin',
        password: 'pass1234',
        email: 'selfadmin@test.com',
        role: UserRole.admin,
        actorRole: UserRole.developer,
      );

      expect(
        () => AdminService.deleteUser(admin.id,
            actorId: admin.id, actorRole: admin.role),
        throwsA(isA<Exception>()),
      );
      expect(
        () => AdminService.toggleUserActive(admin.id,
            actorId: admin.id, actorRole: admin.role),
        throwsA(isA<Exception>()),
      );
      expect(
        () => AdminService.resetPassword(admin.id, 'newpass1',
            actorId: admin.id, actorRole: admin.role),
        throwsA(isA<Exception>()),
      );
    });

    test('مدير يستطيع بنجاح إدارة حساب معلم (الحالة الطبيعية المسموحة)',
        () async {
      await AdminService.initDefaultDeveloper();
      final admin = await AdminService.createUser(
        username: 'goodadmin',
        password: 'pass1234',
        email: 'goodadmin@test.com',
        role: UserRole.admin,
        actorRole: UserRole.developer,
      );
      final teacher = await AdminService.createUser(
        username: 'teacher1',
        password: 'pass1234',
        email: 'teacher1@test.com',
        role: UserRole.teacher,
        actorRole: admin.role,
      );

      // admin يستطيع تجميد المعلم
      await AdminService.toggleUserActive(teacher.id,
          actorId: admin.id, actorRole: admin.role);
      final updated = await AdminService.getUserById(teacher.id);
      expect(updated!.isActive, false);

      // admin يستطيع حذف المعلم
      await AdminService.deleteUser(teacher.id,
          actorId: admin.id, actorRole: admin.role);
      expect(await AdminService.getUserById(teacher.id), null);
    });
  });
}
