import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../models/subscription_model.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

/// شاشة تفعيل الاشتراك بكود
class ActivateSubscriptionScreen extends StatefulWidget {
  const ActivateSubscriptionScreen({super.key});

  @override
  State<ActivateSubscriptionScreen> createState() =>
      _ActivateSubscriptionScreenState();
}

class _ActivateSubscriptionScreenState
    extends State<ActivateSubscriptionScreen>
    with SingleTickerProviderStateMixin {
  final _codeCtrl = TextEditingController();
  bool _isLoading = false;
  String? _errorMsg;
  UserSubscription? _currentSub;
  String? _deviceId;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _loadCurrentSub();
    _loadDeviceId();
  }

  Future<void> _loadDeviceId() async {
    final id = await SubscriptionService.getDeviceId();
    if (mounted) setState(() => _deviceId = id);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSub() async {
    final sub = await SubscriptionService.getCurrentSubscription();
    if (mounted) setState(() => _currentSub = sub);
  }

  Future<void> _activate() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMsg = 'أدخل رمز التفعيل أولاً');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    try {
      final result = await SubscriptionService.activateCode(code);
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (result.isSuccess) {
        _showSuccessDialog(result.message, result.subscription!);
        _codeCtrl.clear();
        await _loadCurrentSub();
      } else {
        setState(() => _errorMsg = result.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMsg = 'حدث خطأ غير متوقع: $e';
      });
    }
  }

  void _showSuccessDialog(String msg, UserSubscription sub) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // أيقونة نجاح كبيرة
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 50,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'تم التفعيل بنجاح! 🎉',
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.2)),
              ),
              child: Text(
                msg,
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  height: 1.7,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            // شارة الخطة الجديدة
            _PlanBadge(plan: sub.planInfo),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Fluttertoast.showToast(
                  msg: 'استمتع بميزات الخطة ${sub.planInfo.nameAr} ✅',
                  backgroundColor: AppColors.success,
                  textColor: Colors.white,
                  toastLength: Toast.LENGTH_LONG,
                );
              },
              child: Text(
                'ابدأ الاستخدام',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: AppColors.primary,
                pinned: true,
                leading: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_forward_rounded,
                      color: Colors.white),
                ),
                title: Text(
                  'تفعيل الاشتراك',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // حالة الاشتراك الحالي
                      if (_currentSub != null) _buildCurrentStatus(),
                      const SizedBox(height: 24),
                      // بطاقة إدخال الكود
                      _buildActivationCard(),
                      const SizedBox(height: 20),
                      // معرّف الجهاز (لطلب كود مخصص من المطور)
                      _buildDeviceIdCard(),
                      const SizedBox(height: 20),
                      // كيفية الحصول على الكود
                      _buildHowToGetCode(),
                      const SizedBox(height: 20),
                      // كود تجريبي مجاني
                      _buildFreeTrial(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStatus() {
    final sub = _currentSub!;
    final info = sub.planInfo;
    final isExpired = sub.isExpired;
    final statusColor = isExpired
        ? AppColors.error
        : sub.isExpiringSoon
            ? AppColors.warning
            : AppColors.success;
    final statusText = isExpired
        ? 'انتهى الاشتراك'
        : sub.isPaid
            ? sub.daysRemaining > 0
                ? 'ينتهي خلال ${sub.daysRemaining} يوم'
                : 'فعّال (لا ينتهي)'
            : 'الخطة المجانية';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              sub.isPaid
                  ? Icons.workspace_premium_rounded
                  : Icons.free_breakfast_rounded,
              color: statusColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الاشتراك الحالي: ${info.nameAr} ${info.badge}',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  statusText,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivationCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.key_rounded,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                'أدخل رمز التفعيل',
                style: GoogleFonts.cairo(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // حقل إدخال الكود
          TextFormField(
            controller: _codeCtrl,
            textDirection: TextDirection.ltr,
            textCapitalization: TextCapitalization.characters,
            style: GoogleFonts.cairo(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
            decoration: InputDecoration(
              hintText: 'مثال: GRADER-PRO-TRIAL',
              hintStyle: GoogleFonts.cairo(
                color: AppColors.textHint,
                fontWeight: FontWeight.normal,
                fontSize: 14,
              ),
              prefixIcon: const Icon(Icons.confirmation_number_outlined,
                  color: AppColors.primary),
              suffixIcon: _codeCtrl.text.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _codeCtrl.clear();
                        setState(() => _errorMsg = null);
                      },
                      icon: Icon(Icons.clear_rounded,
                          color: AppColors.textSecondary),
                    )
                  : IconButton(
                      onPressed: () async {
                        final data =
                            await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null) {
                          _codeCtrl.text = data!.text!.trim().toUpperCase();
                          setState(() {});
                        }
                      },
                      icon: const Icon(Icons.paste_rounded,
                          color: AppColors.primary),
                      tooltip: 'لصق',
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: _errorMsg != null
                      ? AppColors.error
                      : Colors.grey.shade300,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: AppColors.primary, width: 2),
              ),
              errorText: _errorMsg,
              errorStyle: GoogleFonts.cairo(
                fontSize: 12,
                color: AppColors.error,
                height: 1.5,
              ),
              errorMaxLines: 3,
            ),
            onChanged: (_) => setState(() => _errorMsg = null),
            onFieldSubmitted: (_) => _activate(),
          ),
          const SizedBox(height: 16),
          // زر التفعيل
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _activate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 3,
                shadowColor: AppColors.primary.withValues(alpha: 0.4),
              ),
              child: _isLoading
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
                        const Icon(Icons.rocket_launch_rounded),
                        const SizedBox(width: 10),
                        Text(
                          'تفعيل الاشتراك',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceIdCard() {
    final id = _deviceId;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.smartphone_rounded,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'معرّف جهازك (Device ID)',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'أرسل هذا المعرّف للمطوّر عند طلب رمز اشتراك مدفوع؛ سيتم '
            'توليد رمز تفعيل مخصص لهذا الجهاز فقط، ولا يعمل على أي جهاز آخر.',
            style: GoogleFonts.cairo(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: id == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: id));
                    Fluttertoast.showToast(
                      msg: 'تم نسخ معرّف الجهاز ✅',
                      backgroundColor: AppColors.success,
                      textColor: Colors.white,
                    );
                  },
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.copy_rounded,
                      color: AppColors.primary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    id ?? 'جارِ التحميل...',
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      letterSpacing: 1.5,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowToGetCode() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline_rounded,
                  color: AppColors.info, size: 18),
              const SizedBox(width: 8),
              Text(
                'كيف أحصل على رمز التفعيل؟',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _howStep('1', 'تواصل مع المطور م. باسل أشرف عبر واتساب'),
          _howStep('2', 'اختر الخطة المناسبة لك'),
          _howStep('3', 'ادفع الاشتراك وستصلك الرمز فوراً'),
          _howStep('4', 'أدخل الرمز هنا وابدأ الاستخدام'),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              Clipboard.setData(const ClipboardData(text: '01014543845'));
              Fluttertoast.showToast(
                msg: 'تم نسخ رقم واتساب المطور ✅',
                backgroundColor: AppColors.success,
                textColor: Colors.white,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF25D366).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.phone_in_talk_rounded,
                      color: Color(0xFF25D366), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'واتساب: 01014543845 (اضغط للنسخ)',
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      color: const Color(0xFF25D366),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _howStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: AppColors.info,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                num,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFreeTrial() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined,
                  color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              Text(
                'رمز تجريبي مجاني',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'جرّب الخطة الاحترافية مجاناً لمدة 14 يوماً',
            style: GoogleFonts.cairo(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              _codeCtrl.text = 'GRADER-PRO-TRIAL';
              setState(() {});
              Fluttertoast.showToast(
                msg: 'تم لصق الرمز التجريبي — اضغط "تفعيل"',
                backgroundColor: AppColors.info,
                textColor: Colors.white,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.copy_rounded,
                      color: AppColors.warning, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'GRADER-PRO-TRIAL',
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.warning,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'اضغط على الرمز أعلاه لنسخه تلقائياً ثم فعّله',
            style: GoogleFonts.cairo(
              fontSize: 11,
              color: AppColors.textHint,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// شارة الخطة
class _PlanBadge extends StatelessWidget {
  final SubscriptionPlanInfo plan;
  const _PlanBadge({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(plan.badge, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Column(
            children: [
              Text(
                'خطة ${plan.nameAr}',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              Text(
                plan.description,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
