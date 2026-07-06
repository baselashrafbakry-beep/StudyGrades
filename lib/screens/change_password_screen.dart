import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/admin_service.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

/// شاشة تغيير كلمة المرور الذاتية
///
/// 🔒 أُنشئت هذه الشاشة لسدّ ثغرة أمنية/عطل مكتشَف أثناء المراجعة الأمنية
/// الشاملة: كانت خدمة AdminService.resetPassword() تمنع صراحةً أي مستخدم
/// من تغيير كلمة مروره الخاصة وتُحيله إلى "شاشة الملف الشخصي" — وهي شاشة
/// لم تكن موجودة إطلاقاً في التطبيق. هذا يعني أن حساب المطوّر (الذي
/// يُنشأ بكلمة مرور افتراضية مكتوبة في الكود المصدري 'Basel@2026') لم
/// يكن يملك أي وسيلة فعلية لتغيير كلمة مروره عبر واجهة التطبيق.
///
/// [isForced] عندما تكون true (تُستخدَم عند إجبار المطوّر على تغيير كلمة
/// المرور الافتراضية فور أول دخول): يتم إخفاء زر الرجوع/الإلغاء بالكامل
/// ومنع الخروج من الشاشة (WillPopScope) حتى يتم تغيير كلمة المرور بنجاح.
class ChangePasswordScreen extends StatefulWidget {
  final bool isForced;

  const ChangePasswordScreen({super.key, this.isForced = false});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  int _passwordStrength(String p) {
    int s = 0;
    if (p.length >= 6) s++;
    if (p.length >= 10) s++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) s++;
    if (RegExp(r'[0-9]').hasMatch(p)) s++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>_\-]').hasMatch(p)) s++;
    return s.clamp(0, 4);
  }

  Color _strengthColor(int s) {
    switch (s) {
      case 0:
      case 1:
        return AppColors.error;
      case 2:
        return AppColors.warning;
      case 3:
        return AppColors.info;
      default:
        return AppColors.success;
    }
  }

  String _strengthLabel(int s) {
    switch (s) {
      case 0:
      case 1:
        return 'ضعيفة';
      case 2:
        return 'متوسطة';
      case 3:
        return 'جيدة';
      default:
        return 'قوية';
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) {
      _showError('تعذر التحقق من هوية المستخدم الحالي');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await AdminService.changeOwnPassword(
        userId: user.id,
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
      );
      if (!mounted) return;
      Fluttertoast.showToast(
        msg: 'تم تغيير كلمة المرور بنجاح ✅',
        backgroundColor: AppColors.success,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG,
      );
      if (widget.isForced) {
        // بعد التغيير الإجباري الناجح، تابع إلى الشاشة الرئيسية
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: AppColors.error,
      textColor: Colors.white,
      toastLength: Toast.LENGTH_LONG,
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<
        ThemeProvider>(); // يضمن إعادة البناء فوراً عند تبديل الوضع الليلي/الفاتح
    final strength = _passwordStrength(_newCtrl.text);

    return PopScope(
      canPop: !widget.isForced,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.isForced) _buildForcedNotice(),
                        const SizedBox(height: 16),
                        _passwordField(
                          controller: _currentCtrl,
                          label: 'كلمة المرور الحالية',
                          obscure: _obscureCurrent,
                          onToggle: () => setState(
                              () => _obscureCurrent = !_obscureCurrent),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'أدخل كلمة المرور الحالية'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        _passwordField(
                          controller: _newCtrl,
                          label: 'كلمة المرور الجديدة',
                          obscure: _obscureNew,
                          onToggle: () =>
                              setState(() => _obscureNew = !_obscureNew),
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            if (v == null || v.length < 6) {
                              return 'كلمة المرور 6 أحرف على الأقل';
                            }
                            return null;
                          },
                        ),
                        if (_newCtrl.text.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: strength / 4,
                                  minHeight: 6,
                                  borderRadius: BorderRadius.circular(6),
                                  backgroundColor:
                                      Colors.grey.withValues(alpha: 0.2),
                                  color: _strengthColor(strength),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _strengthLabel(strength),
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _strengthColor(strength),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        _passwordField(
                          controller: _confirmCtrl,
                          label: 'تأكيد كلمة المرور الجديدة',
                          obscure: _obscureConfirm,
                          onToggle: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                          validator: (v) {
                            if (v != _newCtrl.text) {
                              return 'كلمتا المرور غير متطابقتين';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _handleSubmit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'حفظ كلمة المرور الجديدة',
                                    style: GoogleFonts.cairo(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForcedNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.security_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'لأمان حسابك، يجب تغيير كلمة المرور الافتراضية قبل المتابعة '
              'لاستخدام التطبيق.',
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.6,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          if (!widget.isForced)
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon:
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            )
          else
            const SizedBox(width: 48),
          Expanded(
            child: Text(
              'تغيير كلمة المرور',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: GoogleFonts.cairo(),
      onChanged: onChanged,
      inputFormatters: [LengthLimitingTextInputFormatter(64)],
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(),
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: AppColors.textHint,
          ),
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      validator: validator,
    );
  }
}
