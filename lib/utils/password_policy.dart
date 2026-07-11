class PasswordPolicy {
  PasswordPolicy._();

  static String? validate(String password, {String? current}) {
    if (password.length < 10 || password.length > 128) {
      return 'يجب أن تتكون كلمة المرور من 10 إلى 128 حرفاً';
    }
    if (!RegExp(r'[A-Za-z\u0600-\u06FF]').hasMatch(password) ||
        !RegExp(r'[0-9\u0660-\u0669]').hasMatch(password)) {
      return 'يجب أن تحتوي كلمة المرور على حرف واحد ورقم واحد على الأقل';
    }
    if (current != null && password == current) {
      return 'يجب أن تختلف كلمة المرور الجديدة عن الحالية';
    }
    return null;
  }
}
