import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';

/// --------------------------------------------------------------------------
/// شاشة "توليد رمز اشتراك مخصص" — نسخة V2 (بعد إصلاح ثغرة تزوير التراخيص)
///
/// ⚠️ تنبيه أمني هام:
/// النسخة القديمة من هذه الشاشة كانت تستدعي مباشرة
/// `SubscriptionService.generatePersonalizedCode()` لتوليد كود موقَّع
/// (كان حينها HMAC/SHA-256 متماثل). المشكلة الجوهرية أن هذه الشاشة
/// موجودة داخل نفس التطبيق الذي يُشحَن لكل عميل، ما يعني أن منطق توليد
/// الأكواد (وبالتالي "السر" في النظام القديم) كان يسافر مع كل نسخة مثبَّتة
/// من التطبيق — بما فيها أجهزة المعلمين العاديين.
///
/// بعد الترقية إلى نظام التوقيع الرقمي غير المتماثل (RSA-2048/PSS)، يتطلب
/// توليد كود جديد امتلاك المفتاح الخاص (Private Key) الذي يبقى حصرياً على
/// جهاز المطوّر خارج هذا التطبيق تماماً — ولا يمكن تضمينه هنا بأي شكل من
/// الأشكال دون إعادة فتح نفس الثغرة القديمة من جديد.
///
/// لذلك، أصبحت وظيفة هذه الشاشة داخل التطبيق قاصرة على "الأداة المساعدة":
/// عرض تعليمات واضحة + الأمر الجاهز الذي يُشغِّله المطوّر على جهازه الخاص
/// باستخدام الأداة الخارجية المستقلة generate_license.py، دون تنفيذ أي
/// عملية تشفير أو توقيع داخل التطبيق نفسه.
/// --------------------------------------------------------------------------
class LicenseGeneratorScreen extends StatefulWidget {
  const LicenseGeneratorScreen({super.key});

  @override
  State<LicenseGeneratorScreen> createState() => _LicenseGeneratorScreenState();
}

class _LicenseGeneratorScreenState extends State<LicenseGeneratorScreen> {
  final _deviceIdCtrl = TextEditingController();
  String _selectedPlan = 'PRO';
  int _days = 30;

  final Map<String, String> _plans = const {
    'BASIC': 'أساسي',
    'PRO': 'احترافي',
    'SCHOOL': 'مدرسة',
  };

  final List<int> _durationOptions = const [7, 14, 30, 90, 180, 365, 9999];

  @override
  void dispose() {
    _deviceIdCtrl.dispose();
    super.dispose();
  }

  String get _generatedCommand {
    final deviceId = _deviceIdCtrl.text.trim().isEmpty
        ? '<DEVICE_ID>'
        : _deviceIdCtrl.text.trim();
    return 'python3 generate_license.py --device-id $deviceId '
        '--plan $_selectedPlan --days $_days';
  }

  void _copyCommand() {
    if (_deviceIdCtrl.text.trim().isEmpty) {
      Fluttertoast.showToast(
        msg: 'أدخل معرّف جهاز العميل أولاً',
        backgroundColor: AppColors.error,
        textColor: Colors.white,
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: _generatedCommand));
    Fluttertoast.showToast(
      msg: 'تم نسخ الأمر ✅ — نفّذه على جهازك (خارج التطبيق)',
      backgroundColor: AppColors.success,
      textColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<
        ThemeProvider>(); // يضمن إعادة البناء فوراً عند تبديل الوضع الليلي/الفاتح
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('توليد رمز اشتراك مخصص',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.security_rounded,
                      color: AppColors.warning, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'لأسباب أمنية (حماية من تزوير الأكواد)، لم يعد توليد '
                      'الأكواد يتم داخل التطبيق مباشرة. المفتاح الخاص للتوقيع '
                      'الرقمي يبقى فقط على جهازك الشخصي، خارج التطبيق تماماً. '
                      'استخدم الأداة الخارجية أدناه لتوليد الكود.',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('معرّف جهاز العميل (Device ID)',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _deviceIdCtrl,
              textDirection: TextDirection.ltr,
              textCapitalization: TextCapitalization.characters,
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold, letterSpacing: 1.2),
              decoration: InputDecoration(
                hintText: 'مثال: A1B2C3D4E5F60708',
                filled: true,
                fillColor: AppColors.cardBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste_rounded),
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (!mounted) return;
                    if (data?.text != null) {
                      _deviceIdCtrl.text = data!.text!.trim().toUpperCase();
                      setState(() {});
                    }
                  },
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Text('الخطة',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _plans.entries.map((e) {
                final selected = _selectedPlan == e.key;
                return ChoiceChip(
                  label: Text(e.value, style: GoogleFonts.cairo()),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedPlan = e.key),
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text('المدة (أيام)',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _durationOptions.map((d) {
                final selected = _days == d;
                return ChoiceChip(
                  label: Text(
                    d == 9999 ? 'دائم' : '$d يوم',
                    style: GoogleFonts.cairo(),
                  ),
                  selected: selected,
                  onSelected: (_) => setState(() => _days = d),
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
            Text('الأمر الجاهز (نفّذه على جهازك الشخصي فقط)',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _generatedCommand,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Color(0xFF9CDCFE),
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _copyCommand,
                icon: const Icon(Icons.copy_rounded),
                label: Text('نسخ الأمر',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.info.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('خطوات الاستخدام:',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.info)),
                  const SizedBox(height: 8),
                  _step('1', 'انسخ الأمر أعلاه بعد إدخال معرّف جهاز العميل'),
                  _step('2', 'شغّل الأمر على جهازك الشخصي داخل مجلد dev_tools'),
                  _step('3', 'انسخ الكود الناتج (يبدأ بـ SGV2-) وأرسله للعميل'),
                  _step(
                      '4', 'العميل يُدخل الكود في شاشة "تفعيل الاشتراك" لديه'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 2),
            decoration: const BoxDecoration(
              color: AppColors.info,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(num,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: GoogleFonts.cairo(
                    fontSize: 12.5, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
