import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/utils/password_policy.dart';

void main() {
  group('PasswordPolicy', () {
    test('accepts strong Arabic and Latin passwords', () {
      expect(PasswordPolicy.validate('NewPassword-456'), isNull);
      expect(PasswordPolicy.validate('مدرسة-آمنة-456'), isNull);
    });

    test('requires ten characters, a letter, and a digit', () {
      expect(PasswordPolicy.validate('short1'), isNotNull);
      expect(PasswordPolicy.validate('allletterslong'), isNotNull);
      expect(PasswordPolicy.validate('123456789012'), isNotNull);
    });

    test('rejects an unchanged password', () {
      expect(
        PasswordPolicy.validate('NewPassword-456', current: 'NewPassword-456'),
        isNotNull,
      );
    });
  });
}
