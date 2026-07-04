// اختبار حي فعلي (Live Functional Test) لإصلاح ثغرة تجارية جسيمة:
// "حد عدد المعلمين" (Seat Limits / maxTeachers) — تم اكتشافها أثناء
// تدقيق Pillar 2 (الإعداد التجاري والاشتراكات).
//
// 🔴 المشكلة الأصلية المُكتشَفة:
// كان الحقل `maxTeachers` موجوداً في `SubscriptionPlanInfo` ومعروضاً
// فعلياً في شاشة الأسعار كرقم تسويقي ("1 معلم" / "غير محدود")، لكن
// `AdminService.createUser()` لم تكن تتحقق منه إطلاقاً — أي باقة (حتى
// المجانية التي تنص على "معلم واحد فقط") كانت تسمح بإنشاء عدد غير
// محدود من حسابات المعلمين، مما يفرّغ نموذج التسعير القائم على عدد
// المقاعد من أي قيمة تجارية فعلية.
//
// ✅ الإصلاح: `AdminService.createUser()` و `toggleUserActive()` الآن
// يتحققان من `SubscriptionService.getMaxTeachers()` قبل السماح بإنشاء
// حساب معلم جديد أو إعادة تفعيل حساب معلم مجمَّد، ويرفضان العملية إذا
// كان عدد حسابات المعلمين النشطة يساوي أو يتجاوز حد الباقة الحالية.

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_grades_voice/models/subscription_model.dart';
import 'package:study_grades_voice/models/user_model.dart';
import 'package:study_grades_voice/services/admin_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_seat_limits_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings_box');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> setPlan(SubscriptionPlan plan) async {
    final sub = UserSubscription(
      plan: plan,
      startDate: DateTime.now(),
      expiryDate: DateTime.now().add(const Duration(days: 30)),
      isActive: true,
      daysRemaining: 30,
    );
    final box = Hive.box('settings_box');
    await box.put('subscription_data', jsonEncode(sub.toJson()));
  }

  group('AdminService.createUser — فرض حد عدد المعلمين (Seat Limits)', () {
    test(
        'خطة مجاني/أساسي/احترافي (حد معلم واحد): محاولة إنشاء معلم ثانٍ تُرفَض',
        () async {
      await setPlan(SubscriptionPlan.pro); // maxTeachers = 1
      await AdminService.initDefaultDeveloper();

      // أول معلم يجب أن يُقبَل (0 حالياً < 1)
      final t1 = await AdminService.createUser(
        username: 'teacher_one',
        password: 'pass1234',
        email: 't1@test.com',
        role: UserRole.teacher,
        actorRole: UserRole.developer,
      );
      expect(t1.role, UserRole.teacher);

      // المعلم الثاني يجب أن يُرفَض (1 نشط >= 1 حد)
      expect(
        () => AdminService.createUser(
          username: 'teacher_two',
          password: 'pass1234',
          email: 't2@test.com',
          role: UserRole.teacher,
          actorRole: UserRole.developer,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('خطة مدرسة (school): لا يوجد أي حد على عدد المعلمين', () async {
      await setPlan(SubscriptionPlan.school); // maxTeachers = -1
      await AdminService.initDefaultDeveloper();

      for (var i = 1; i <= 10; i++) {
        final t = await AdminService.createUser(
          username: 'teacher_$i',
          password: 'pass1234',
          email: 'teacher$i@test.com',
          role: UserRole.teacher,
          actorRole: UserRole.developer,
        );
        expect(t.role, UserRole.teacher);
      }
      final all = await AdminService.getAllUsers();
      expect(all.where((u) => u.role == UserRole.teacher).length, 10);
    });

    test('حسابات المدير/المشرف لا تُستهلك من حد المعلمين إطلاقاً', () async {
      await setPlan(SubscriptionPlan.pro); // maxTeachers = 1
      await AdminService.initDefaultDeveloper();

      // إنشاء عدة حسابات admin/manager يجب ألا يؤثر على حد المعلمين
      await AdminService.createUser(
        username: 'admin1',
        password: 'pass1234',
        email: 'admin1@test.com',
        role: UserRole.admin,
        actorRole: UserRole.developer,
      );
      await AdminService.createUser(
        username: 'manager1',
        password: 'pass1234',
        email: 'manager1@test.com',
        role: UserRole.manager,
        actorRole: UserRole.developer,
      );

      // ما زال بإمكاننا إنشاء المعلم الأول (المقعد الوحيد المتاح)
      final t1 = await AdminService.createUser(
        username: 'teacher_only',
        password: 'pass1234',
        email: 'teacheronly@test.com',
        role: UserRole.teacher,
        actorRole: UserRole.developer,
      );
      expect(t1.role, UserRole.teacher);
    });

    test(
        'حساب معلم مجمَّد (isActive=false) لا يُحتسَب ضمن الحد — يُتيح '
        'إنشاء معلم جديد بديل', () async {
      await setPlan(SubscriptionPlan.basic); // maxTeachers = 1
      await AdminService.initDefaultDeveloper();

      final t1 = await AdminService.createUser(
        username: 'old_teacher',
        password: 'pass1234',
        email: 'old@test.com',
        role: UserRole.teacher,
        actorRole: UserRole.developer,
      );

      // نجمّد المعلم الأول
      await AdminService.toggleUserActive(t1.id,
          actorId: 1, actorRole: UserRole.developer);
      final frozen = await AdminService.getUserById(t1.id);
      expect(frozen!.isActive, false);

      // الآن يمكن إنشاء معلم جديد بديل (المقعد أصبح متاحاً)
      final t2 = await AdminService.createUser(
        username: 'new_teacher',
        password: 'pass1234',
        email: 'new@test.com',
        role: UserRole.teacher,
        actorRole: UserRole.developer,
      );
      expect(t2.role, UserRole.teacher);
    });
  });

  group('AdminService.toggleUserActive — فرض الحد عند إعادة التفعيل', () {
    test('إعادة تفعيل معلم مجمَّد تُرفَض إذا امتلأ الحد بمعلم آخر نشط بالفعل',
        () async {
      await setPlan(SubscriptionPlan.basic); // maxTeachers = 1
      await AdminService.initDefaultDeveloper();

      final t1 = await AdminService.createUser(
        username: 'teacher_a',
        password: 'pass1234',
        email: 'a@test.com',
        role: UserRole.teacher,
        actorRole: UserRole.developer,
      );
      // نجمّد t1 ثم ننشئ t2 بديلاً (يملأ المقعد الوحيد المتاح)
      await AdminService.toggleUserActive(t1.id,
          actorId: 1, actorRole: UserRole.developer);
      final t2 = await AdminService.createUser(
        username: 'teacher_b',
        password: 'pass1234',
        email: 'b@test.com',
        role: UserRole.teacher,
        actorRole: UserRole.developer,
      );
      expect(t2.isActive, true);

      // الآن محاولة إعادة تفعيل t1 (المجمَّد) يجب أن تُرفَض لأن t2 يشغل
      // المقعد الوحيد المتاح في هذه الباقة
      expect(
        () => AdminService.toggleUserActive(t1.id,
            actorId: 1, actorRole: UserRole.developer),
        throwsA(isA<Exception>()),
      );
    });

    test('تجميد معلم نشط (وليس إعادة تفعيله) لا يخضع أبداً لفحص الحد',
        () async {
      await setPlan(SubscriptionPlan.basic); // maxTeachers = 1
      await AdminService.initDefaultDeveloper();

      final t1 = await AdminService.createUser(
        username: 'teacher_solo',
        password: 'pass1234',
        email: 'solo@test.com',
        role: UserRole.teacher,
        actorRole: UserRole.developer,
      );

      // التجميد (تعطيل) يجب أن ينجح دائماً بلا أي قيد متعلق بالحد
      await AdminService.toggleUserActive(t1.id,
          actorId: 1, actorRole: UserRole.developer);
      final frozen = await AdminService.getUserById(t1.id);
      expect(frozen!.isActive, false);
    });
  });
}
