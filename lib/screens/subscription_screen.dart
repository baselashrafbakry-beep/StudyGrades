import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../models/subscription_model.dart';
import '../services/admin_service.dart';
import '../theme/app_theme.dart';

/// شاشة خطط الاشتراك الاحترافية
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with SingleTickerProviderStateMixin {
  bool _yearlyBilling = false;
  SubscriptionPlan _selectedPlan = SubscriptionPlan.pro;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            children: [
              _buildHeader(),
              _buildBillingToggle(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      ...SubscriptionPlans.all.map(
                        (plan) => _buildPlanCard(plan),
                      ),
                      const SizedBox(height: 20),
                      _buildContactCard(),
                      const SizedBox(height: 20),
                      _buildFeaturesComparison(),
                      const SizedBox(height: 24),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_rounded,
                    color: Colors.white),
              ),
              Expanded(
                child: Text(
                  'خطط الاشتراك',
                  style: GoogleFonts.cairo(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'اختر الخطة المناسبة لاحتياجاتك',
            style: GoogleFonts.cairo(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingToggle() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _yearlyBilling = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color:
                      !_yearlyBilling ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Text(
                  'شهري',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    color: !_yearlyBilling
                        ? Colors.white
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _yearlyBilling = true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color:
                      _yearlyBilling ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'سنوي',
                      style: GoogleFonts.cairo(
                        color: _yearlyBilling
                            ? Colors.white
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'وفّر 25%',
                        style: GoogleFonts.cairo(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
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
    );
  }

  Widget _buildPlanCard(SubscriptionPlanInfo plan) {
    final isSelected = _selectedPlan == plan.plan;
    final isPro = plan.plan == SubscriptionPlan.pro;
    final price = _yearlyBilling ? plan.priceYearly : plan.priceMonthly;
    final color = Color(
      int.parse(plan.colorHex.replaceAll('#', '0xFF')),
    );

    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = plan.plan),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (isSelected ? color : Colors.black)
                  .withValues(alpha: isSelected ? 0.15 : 0.06),
              blurRadius: isSelected ? 16 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // رأس البطاقة
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isPro ? color : color.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(13),
                ),
              ),
              child: Row(
                children: [
                  Text(plan.badge, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              plan.nameAr,
                              style: GoogleFonts.cairo(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isPro ? Colors.white : color,
                              ),
                            ),
                            if (isPro) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'الأكثر شيوعاً',
                                  style: GoogleFonts.cairo(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          plan.description,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: isPro
                                ? Colors.white.withValues(alpha: 0.85)
                                : color.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        price == 0
                            ? (plan.plan == SubscriptionPlan.free
                                ? 'مجاني'
                                : 'تواصل معنا')
                            : '${price.toInt()}',
                        style: GoogleFonts.cairo(
                          fontSize: price == 0 ? 16 : 24,
                          fontWeight: FontWeight.bold,
                          color: isPro ? Colors.white : color,
                        ),
                      ),
                      if (price > 0)
                        Text(
                          _yearlyBilling ? 'جنيه/سنة' : 'جنيه/شهر',
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            color: isPro
                                ? Colors.white70
                                : color.withValues(alpha: 0.7),
                          ),
                        ),
                      if (_yearlyBilling && plan.priceMonthly > 0)
                        Text(
                          'وفّر ${plan.yearlyDiscount.toInt()}%',
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            color: isPro ? Colors.amber : AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // ميزات الخطة
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildFeatureRow(
                    '👩‍🏫 المعلمون',
                    plan.isUnlimitedTeachers
                        ? 'غير محدود'
                        : '${plan.maxTeachers} معلم',
                    color,
                  ),
                  _buildFeatureRow(
                    '👨‍🎓 الطلاب/الفصل',
                    plan.isUnlimitedStudents
                        ? 'غير محدود'
                        : 'حتى ${plan.maxStudentsPerClass} طالب',
                    color,
                  ),
                  _buildFeatureRow(
                    '🏫 الفصول',
                    plan.isUnlimitedClasses
                        ? 'غير محدود'
                        : 'حتى ${plan.maxClassesPerTeacher} فصل',
                    color,
                  ),
                  _buildFeatureRow(
                      '🎤 الإدخال الصوتي', plan.voiceInput ? '✅' : '❌', color),
                  _buildFeatureRow(
                      '📶 مزامنة أوفلاين', plan.offlineSync ? '✅' : '❌', color),
                  _buildFeatureRow(
                      '📊 تحليلات متقدمة', plan.analytics ? '✅' : '❌', color),
                  _buildFeatureRow(
                      '📤 تصدير Excel', plan.exportExcel ? '✅' : '❌', color),
                  _buildFeatureRow(
                      '⚙️ لوحة الإدارة', plan.adminPanel ? '✅' : '❌', color),
                  _buildFeatureRow(
                      '🎯 دعم أولوية', plan.prioritySupport ? '✅' : '❌', color),
                  const SizedBox(height: 12),
                  if (plan.plan != SubscriptionPlan.free)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isSelected ? color : color.withValues(alpha: 0.1),
                          foregroundColor: isSelected ? Colors.white : color,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => _onSubscribe(plan),
                        child: Text(
                          plan.plan == SubscriptionPlan.school
                              ? 'تواصل معنا'
                              : isSelected
                                  ? 'اشترك الآن ← اتصل بالمطور'
                                  : 'اختر هذه الخطة',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: value == '✅'
                  ? AppColors.success
                  : value == '❌'
                      ? AppColors.textHint
                      : color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.1),
            AppColors.accent.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.support_agent_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تواصل مع المطور',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      AdminService.developerName,
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildContactRow(
            Icons.phone_rounded,
            'واتساب',
            AdminService.developerPhone,
            onTap: () => _copyToClipboard(AdminService.developerPhone),
          ),
          const SizedBox(height: 8),
          _buildContactRow(
            Icons.email_rounded,
            'البريد الإلكتروني',
            AdminService.developerEmail,
            onTap: () => _copyToClipboard(AdminService.developerEmail),
          ),
        ],
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String label, String value,
      {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    value,
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.copy_rounded, color: AppColors.textHint, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesComparison() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '✨ مزايا التطبيق',
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ..._appFeatures.map((f) => _buildAppFeatureTile(f)),
      ],
    );
  }

  static const List<_AppFeature> _appFeatures = [
    _AppFeature(
      icon: '🎤',
      title: 'إدخال صوتي باللهجة المصرية',
      desc: 'سجّل الدرجات بصوتك بالعربية المصرية دون كتابة',
    ),
    _AppFeature(
      icon: '⚡',
      title: 'وضع ذكي تلقائي',
      desc: 'انتقال تلقائي بين الطلاب والبنود بعد كل درجة',
    ),
    _AppFeature(
      icon: '📶',
      title: 'يعمل أوفلاين',
      desc: 'سجّل الدرجات بدون إنترنت وزامنها لاحقاً',
    ),
    _AppFeature(
      icon: '📊',
      title: 'تحليلات وإحصاءات',
      desc: 'رسوم بيانية تفاعلية وإحصاءات أداء الطلاب',
    ),
    _AppFeature(
      icon: '📤',
      title: 'تصدير Excel و CSV',
      desc: 'صدّر كشف الدرجات بالصيغة الرسمية المصرية',
    ),
    _AppFeature(
      icon: '🔒',
      title: 'أمان وخصوصية',
      desc: 'بيانات الطلاب محفوظة محلياً على جهازك فقط',
    ),
  ];

  Widget _buildAppFeatureTile(_AppFeature feature) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(feature.icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  feature.desc,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
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

  void _onSubscribe(SubscriptionPlanInfo plan) {
    if (plan.plan == SubscriptionPlan.school) {
      _showContactDialog();
      return;
    }
    _showSubscribeDialog(plan);
  }

  void _showSubscribeDialog(SubscriptionPlanInfo plan) {
    final price = _yearlyBilling ? plan.priceYearly : plan.priceMonthly;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Text(plan.badge, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 8),
            Text(
              'الاشتراك في ${plan.nameAr}',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'لإتمام الاشتراك، تواصل مع المطور مباشرة:',
              style: GoogleFonts.cairo(fontSize: 14),
            ),
            const SizedBox(height: 12),
            _infoRow('📱 واتساب:', AdminService.developerPhone),
            _infoRow('📧 البريد:', AdminService.developerEmail),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '💰 السعر: ${price.toInt()} جنيه / ${_yearlyBilling ? "سنة" : "شهر"}',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إغلاق', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _copyToClipboard(AdminService.developerPhone);
            },
            child: Text(
              'نسخ رقم الواتساب',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showContactDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          '🏫 خطة المدرسة',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'للمدارس والمؤسسات التعليمية، تواصل مع المطور للحصول على عرض سعر مخصص:',
              style: GoogleFonts.cairo(fontSize: 14),
            ),
            const SizedBox(height: 12),
            _infoRow('م. باسل أشرف', ''),
            _infoRow('📱 واتساب:', AdminService.developerPhone),
            _infoRow('📧 البريد:', AdminService.developerEmail),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إغلاق', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _copyToClipboard(AdminService.developerPhone);
            },
            child: Text(
              'نسخ الواتساب',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          if (value.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                value,
                style: GoogleFonts.cairo(fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    Fluttertoast.showToast(
      msg: 'تم النسخ: $text',
      backgroundColor: AppColors.success,
      textColor: Colors.white,
    );
  }
}

class _AppFeature {
  final String icon;
  final String title;
  final String desc;

  const _AppFeature({
    required this.icon,
    required this.title,
    required this.desc,
  });
}
