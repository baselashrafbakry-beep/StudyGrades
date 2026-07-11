import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/models/subscription_model.dart';
import 'package:study_grades_voice/models/user_model.dart';

void main() {
  group('User parsing', () {
    test('normalizes role and parses string booleans', () {
      final user = User.fromJson({
        'id': '7',
        'username': 'teacher',
        'email': 'teacher@example.com',
        'role': ' Admin ',
        'is_active': 'false',
      });

      expect(user.id, 7);
      expect(user.role, UserRole.admin);
      expect(user.isActive, isFalse);
    });

    test('falls back unknown roles to teacher', () {
      final user = User.fromJson({
        'id': 8,
        'username': 'unknown',
        'email': '',
        'role': 'superuser',
      });

      expect(user.role, UserRole.teacher);
      expect(user.canManageUsers, isFalse);
    });

    test('parses top-level subscription fields', () {
      final user = User.fromJson({
        'id': 9,
        'username': 'school-admin',
        'email': 'admin@example.com',
        'role': 'admin',
        'subscription_plan': 'school',
        'subscription_status': 'active',
      });

      expect(user.subscription.plan, SubscriptionPlan.school);
      expect(user.subscription.isUsable, isTrue);
      expect(user.canManageUsers, isTrue);
    });

    test('admin cannot manage users when plan does not allow it', () {
      final user = User.fromJson({
        'id': 10,
        'username': 'limited-admin',
        'email': 'limited@example.com',
        'role': 'admin',
        'subscription': {'plan': 'starter', 'status': 'active'},
      });

      expect(user.canAccessAdminPanel, isTrue);
      expect(user.canManageUsers, isFalse);
    });
  });
}
