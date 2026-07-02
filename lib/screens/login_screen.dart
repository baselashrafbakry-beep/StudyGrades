import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/grading_provider.dart';
import '../services/admin_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';
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
  bool _showDemoTip = false;
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
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'LoginScreen.loadRemembered');
    }
  }

  Future<void> _saveRememberedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString(_rememberKey, _userCtrl.text.trim());
      } else {
        await prefs.remove(_rememberKey);
      }
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'LoginScreen.saveRemembered');
    }
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  // تقييم قوة كلمة المرور (0-4)
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

  /// تحويل رسالة خطأ API إلى نص عربي مفهوم للمستخدم
  String _humanizeError(String rawError) {
    final e = rawError.toLowerCase();
    if (e.contains('connection') || e.contains('timeout') || e.contains('network') || e.contains('connectederror')) {
      return 'تعذر الاتصال بالسيرفر\nتحقق من الإنترنت أو جرّب الوضع التجريبي';
    }
    if (e.contains('401') || e.contains('unauthorized') || e.contains('بيانات الدخول') || e.contains('غير صحيحة')) {
      return 'اسم المستخدم أو كلمة المرور غير صحيحة';
    }
    if (e.contains('403') || e.contains('forbidden')) {
      return 'ليس لديك صلاحية الدخول، تواصل مع المدير';
    }
    if (e.contains('500') || e.contains('server error')) {
      return 'خطأ في السيرفر، حاول مرة أخرى لاحقاً';
    }
    if (e.contains('انتهت مهلة') || e.contains('مهلة')) {
      return 'انتهت مهلة الاتصال\nالسيرفر بطيء، حاول مرة أخرى';
    }
    if (e.contains('no address associated') || e.contains('socketexception')) {
      return 'لا يوجد اتصال بالإنترنت\nيمكنك استخدام الوضع التجريبي';
    }
    // إن لم تطابق أي حالة، أعد رسالة مبسطة
    if (rawError.length > 80) {
      return 'فشل تسجيل الدخول — تحقق من البيانات أو الاتصال';
    }
    return rawError;
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
        msg: 'مرحباً ${_userCtrl.text.trim()}! تم تسجيل الدخول بنجاح ✅',
        backgroundColor: AppColors.success,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      // إظهار خطأ مفهوم بدلاً من رسالة تقنية
      final raw = auth.error ?? 'فشل تسجيل الدخول';
      final friendly = _humanizeError(raw);
      _showErrorDialog(friendly);
      // إظهار تلميح الوضع التجريبي عند خطأ الاتصال
      if (raw.toLowerCase().contains('connection') ||
          raw.toLowerCase().contains('timeout') ||
          raw.toLowerCase().contains('network') ||
          raw.toLowerCase().contains('socketexception') ||
          raw.toLowerCase().contains('no address')) {
        setState(() => _showDemoTip = true);
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.error_outline_rounded,
                  color: AppColors.error, size: 22),
            ),
            const SizedBox(width: 10),
            Text(
              'تعذر تسجيل الدخول',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.error,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Text(
              message,
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: AppColors.textPrimary,
                height: 1.6,
              ),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 16),
            // زر الوضع التجريبي داخل الحوار عند الخطأ
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _enterDemoMode();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.play_circle_outline,
                        color: AppColors.info, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'جرّب الوضع التجريبي بدون إنترنت',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          color: AppColors.info,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'حاول مرة أخرى',
              style: GoogleFonts.cairo(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// الوضع التجريبي — دخول مباشر بدون حساب
  void _enterDemoMode() {
    final grading = context.read<GradingProvider>();
    grading.loadDemoClassroom(className: 'فصل تجريبي أ', subject: 'عام');
    Fluttertoast.showToast(
      msg: '🎯 وضع تجريبي — بيانات افتراضية',
      backgroundColor: AppColors.info,
      textColor: Colors.white,
      toastLength: Toast.LENGTH_LONG,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final pwdStrength = _passwordStrength(_passCtrl.text);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF5F7FA), Color(0xFFE3F2FD)],
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
                        AdminService.appName,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        AdminService.appNameAr,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 30),
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
                      // تلميح الوضع التجريبي (يظهر بعد خطأ اتصال)
                      if (_showDemoTip) ...[
                        const SizedBox(height: 14),
                        _buildDemoTip(),
                      ],
                      const SizedBox(height: 20),
                      _buildServerInfo(),
                      const Divider(height: 36, thickness: 0.5),
                      _buildDemoButton(),
                      const SizedBox(height: 24),
                      _buildFooter(),
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
        builder: (ctx, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Hero(
          tag: 'appLogo',
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                'assets/icons/app_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.mic_rounded,
                  size: 64,
                  color: Colors.white,
                ),
              ),
            ),
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
        prefixIcon: const Icon(Icons.person_outline, color: AppColors.primary),
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
          tooltip: _obscure ? 'إظهار' : 'إخفاء',
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
                    onChanged: (v) => setState(() => _rememberMe = v ?? false),
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

  Widget _buildDemoTip() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded,
              color: AppColors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'مشكلة في الاتصال؟ جرّب الوضع التجريبي أدناه',
              style: GoogleFonts.cairo(
                fontSize: 12,
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _showDemoTip = false),
            child: const Icon(Icons.close, size: 16, color: AppColors.warning),
          ),
        ],
      ),
    );
  }

  Widget _buildServerInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
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
                  'السيرفر الرسمي',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  AdminService.serverUrl,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // زر نسخ السيرفر
          IconButton(
            onPressed: () {
              Clipboard.setData(const ClipboardData(
                text: AdminService.serverUrlFull,
              ));
              Fluttertoast.showToast(
                msg: 'تم نسخ رابط السيرفر',
                backgroundColor: AppColors.success,
                textColor: Colors.white,
              );
            },
            icon: const Icon(Icons.copy_rounded,
                size: 16, color: AppColors.primary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'نسخ الرابط',
          ),
        ],
      ),
    );
  }

  Widget _buildDemoButton() {
    return OutlinedButton.icon(
      onPressed: _enterDemoMode,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.info),
        foregroundColor: AppColors.info,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.science_outlined, size: 20),
      label: Text(
        'الوضع التجريبي (بدون إنترنت)',
        style: GoogleFonts.cairo(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        GestureDetector(
          onTap: _showDeveloperContact,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_outline,
                  size: 14, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text(
                '${AdminService.developerName} | v${AdminService.appVersion}',
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '© ${AdminService.copyrightYear} ${AdminService.appName}',
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(
            fontSize: 10,
            color: AppColors.textHint.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.help_outline_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'كيف تسجل الدخول؟',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _helpItem(Icons.person_outline,
                'استخدم اسم المستخدم وكلمة المرور الخاصة بك من إدارة المدرسة'),
            const SizedBox(height: 10),
            _helpItem(Icons.wifi_outlined,
                'تأكد من اتصالك بالإنترنت أثناء أول تسجيل دخول'),
            const SizedBox(height: 10),
            _helpItem(Icons.admin_panel_settings_outlined,
                'في حال نسيت كلمة المرور، تواصل مع المدير المسؤول'),
            const SizedBox(height: 10),
            _helpItem(Icons.science_outlined,
                'يمكنك تجربة النظام بدون حساب عبر "الوضع التجريبي"'),
            const Divider(height: 20),
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _showDeveloperContact();
              },
              child: Row(
                children: [
                  const Icon(Icons.support_agent_outlined,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'تواصل مع المطور: ${AdminService.developerName}',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
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

  Widget _helpItem(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.cairo(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  void _showDeveloperContact() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.engineering_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              'تواصل مع المطور',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _contactRow(Icons.person_rounded, 'الاسم',
                AdminService.developerName, false),
            const SizedBox(height: 10),
            _contactRow(Icons.phone_rounded, 'واتساب',
                AdminService.developerPhone, true),
            const SizedBox(height: 10),
            _contactRow(Icons.email_rounded, 'البريد',
                AdminService.developerEmail, true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إغلاق', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _contactRow(
      IconData icon, String label, String value, bool canCopy) {
    return GestureDetector(
      onTap: canCopy
          ? () {
              Clipboard.setData(ClipboardData(text: value));
              Fluttertoast.showToast(
                msg: 'تم النسخ ✅',
                backgroundColor: AppColors.success,
                textColor: Colors.white,
              );
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 18),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: AppColors.textHint,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (canCopy)
              const Icon(Icons.copy_rounded,
                  size: 14, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}
