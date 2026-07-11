import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../utils/password_policy.dart';
import 'login_screen.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _hideCurrent = true;
  bool _hideNew = true;
  bool _hideConfirmation = true;
  bool _submitting = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _formKey.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await context.read<AuthProvider>().changePassword(
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تغيير كلمة المرور. سجّل الدخول مرة أخرى.',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (error) {
      if (!mounted) return;
      final message = error
          .toString()
          .replaceFirst('Exception: ', '')
          .replaceFirst('DioException: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.cairo()),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('تغيير كلمة المرور')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.security_rounded, color: AppColors.info),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'سيتم تسجيل خروج جميع الأجهزة بعد التغيير لحماية الحساب.',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _passwordField(
                      controller: _currentController,
                      label: 'كلمة المرور الحالية',
                      hidden: _hideCurrent,
                      maxLength: 256,
                      autofillHints: const [AutofillHints.password],
                      onToggle: () =>
                          setState(() => _hideCurrent = !_hideCurrent),
                      validator: (value) => value == null || value.isEmpty
                          ? 'أدخل كلمة المرور الحالية'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    _passwordField(
                      controller: _newController,
                      label: 'كلمة المرور الجديدة',
                      hidden: _hideNew,
                      maxLength: 128,
                      autofillHints: const [AutofillHints.newPassword],
                      onToggle: () => setState(() => _hideNew = !_hideNew),
                      validator: (value) => PasswordPolicy.validate(
                        value ?? '',
                        current: _currentController.text,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _passwordField(
                      controller: _confirmationController,
                      label: 'تأكيد كلمة المرور الجديدة',
                      hidden: _hideConfirmation,
                      maxLength: 128,
                      autofillHints: const [AutofillHints.newPassword],
                      onToggle: () => setState(
                        () => _hideConfirmation = !_hideConfirmation,
                      ),
                      validator: (value) => value != _newController.text
                          ? 'كلمتا المرور غير متطابقتين'
                          : null,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.password_rounded),
                        label: Text(
                          _submitting ? 'جارٍ التحديث...' : 'تحديث كلمة المرور',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool hidden,
    required int maxLength,
    required Iterable<String> autofillHints,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: hidden,
      autofillHints: autofillHints,
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
      onFieldSubmitted: onSubmitted,
      validator: validator,
      style: GoogleFonts.cairo(),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          tooltip: hidden ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
          onPressed: onToggle,
          icon: Icon(
            hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          ),
        ),
      ),
    );
  }
}
