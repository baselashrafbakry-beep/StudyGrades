import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _rememberMe = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  static const _rememberKey = 'remember_user';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward();
    _loadRememberedUser();
  }

  Future<void> _loadRememberedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_rememberKey);
      if (saved != null && saved.isNotEmpty) {
        setState(() {
          _userCtrl.text = saved;
          _rememberMe = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveRememberedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString(_rememberKey, _userCtrl.text.trim());
      } else {
        await prefs.remove(_rememberKey);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  /// تقييم قوة كلمة المرور (0-4)
  int _passwordStrength(String pwd) {
    if (pwd.isEmpty) return 0;
    int score = 0;
    if (pwd.length >= 6) score++;
    if (pwd.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(pwd) || RegExp(r'[a-z]').hasMatch(pwd)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(pwd)) score++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=]').hasMatch(pwd)) score++;
    return score.clamp(0, 4);
  }

  String _strengthLabel(int s) {
    switch (s) {
      case 0:
        return '';
      case 1:
        return 'ضعيفة جداً';
      case 2:
        return 'ضعيفة';
      case 3:
        return 'متوسطة';
      case 4:
        return 'قوية';
      default:
        return '';
    }
  }

  Color _strengthColor(int s) {
    switch (s) {
      case 1:
        return AppColors.error;
      case 2:
        return AppColors.warning;
      case 3:
        return AppColors.info;
      case 4:
        return AppColors.success;
      default:
        return Colors.grey;
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    FocusScope.of(context).unfocus();
    await _saveRememberedUser();
    final ok = await auth.login(_userCtrl.text.trim(), _passCtrl.text);
    if (!mounted) return;
    if (ok) {
      Fluttertoast.showToast(
        msg: 'مرحباً بك! تم تسجيل الدخول بنجاح',
        backgroundColor: AppColors.success,
        textColor: Colors.white,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Fluttertoast.showToast(
        msg: auth.error ?? 'فشل تسجيل الدخول',
        backgroundColor: AppColors.error,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final pwdStrength = _passwordStrength(_passCtrl.text);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFF5F7FA),
              Color(0xFFE3F2FD),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 30),
                      _buildLogo(),
                      const SizedBox(height: 24),
                      Text(
                        'StudyGrades 2026',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'سجل دخولك لبدء رصد الدرجات صوتياً',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 36),
                      _buildUserField(),
                      const SizedBox(height: 16),
                      _buildPasswordField(),
                      if (_passCtrl.text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildStrengthIndicator(pwdStrength),
                      ],
                      const SizedBox(height: 12),
                      _buildRememberRow(),
                      const SizedBox(height: 24),
                      _buildLoginButton(auth),
                      const SizedBox(height: 24),
                      _buildServerInfo(),
                      const SizedBox(height: 30),
                      Center(
                        child: Text(
                          '© 2026 StudyGrades — للمعلم باسل أشرف',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.85, end: 1.0),
        duration: const Duration(milliseconds: 800),
        curve: Curves.elasticOut,
        builder: (ctx, scale, child) => Transform.scale(
          scale: scale,
          child: child,
        ),
        child: Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.mic_rounded,
            size: 64,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildUserField() {
    return TextFormField(
      controller: _userCtrl,
      textDirection: TextDirection.ltr,
      style: GoogleFonts.cairo(),
      decoration: InputDecoration(
        labelText: 'اسم المستخدم',
        hintText: 'أدخل اسم المستخدم',
        prefixIcon: const Icon(Icons.person_outline,
            color: AppColors.primary),
        labelStyle: GoogleFonts.cairo(),
        hintStyle: GoogleFonts.cairo(color: AppColors.textHint),
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'الرجاء إدخال اسم المستخدم' : null,
      textInputAction: TextInputAction.next,
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passCtrl,
      obscureText: _obscure,
      textDirection: TextDirection.ltr,
      style: GoogleFonts.cairo(),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: 'كلمة المرور',
        hintText: 'أدخل كلمة المرور',
        prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary),
        suffixIcon: IconButton(
          icon: Icon(
            _obscure ? Icons.visibility : Icons.visibility_off,
            color: AppColors.textSecondary,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
        labelStyle: GoogleFonts.cairo(),
        hintStyle: GoogleFonts.cairo(color: AppColors.textHint),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? 'أدخل كلمة المرور' : null,
      onFieldSubmitted: (_) => _handleLogin(),
    );
  }

  Widget _buildStrengthIndicator(int strength) {
    final color = _strengthColor(strength);
    final label = _strengthLabel(strength);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: strength / 4,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildRememberRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        InkWell(
          onTap: () => setState(() => _rememberMe = !_rememberMe),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _rememberMe,
                    activeColor: AppColors.primary,
                    onChanged: (v) =>
                        setState(() => _rememberMe = v ?? false),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'تذكرني',
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: _showHelpDialog,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'هل تحتاج مساعدة؟',
            style: GoogleFonts.cairo(
              fontSize: 12,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton(AuthProvider auth) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: auth.isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 4,
          shadowColor: AppColors.primary.withValues(alpha: 0.4),
        ),
        child: auth.isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.login_rounded),
                  const SizedBox(width: 10),
                  Text(
                    'تسجيل الدخول',
                    style: GoogleFonts.cairo(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildServerInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_done_outlined,
              color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'متصل بسيرفر آمن',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  'studygrades2026.pythonanywhere.com',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.help_outline_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'تحتاج مساعدة؟',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '• استخدم اسم المستخدم وكلمة المرور التي حصلت عليها من إدارة المدرسة.',
              style: GoogleFonts.cairo(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              '• تأكد من اتصالك بالإنترنت أثناء أول تسجيل دخول.',
              style: GoogleFonts.cairo(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              '• في حال نسيت كلمة المرور، تواصل مع المدير المسؤول.',
              style: GoogleFonts.cairo(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('حسناً', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }
}
