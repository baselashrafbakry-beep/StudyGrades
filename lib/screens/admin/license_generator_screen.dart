import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/subscription_service.dart';
import '../../theme/app_theme.dart';

/// أداة المطوّر لتوليد أكواد اشتراك مخصصة لجهاز عميل معيّن.
/// يضمن هذا أن كل كود مدفوع يعمل فقط على الجهاز الذي طلبه العميل،
/// ويمنع مشاركة/تسريب كود واحد على عدد غير محدود من الأجهزة.
class LicenseGeneratorScreen extends StatefulWidget {
  const LicenseGeneratorScreen({super.key});

  @override
  State<LicenseGeneratorScreen> createState() =>
      _LicenseGeneratorScreenState();
}

class _LicenseGeneratorScreenState extends State<LicenseGeneratorScreen> {
  final _deviceIdCtrl = TextEditingController();
  String _selectedPlan = 'PRO';
  int _days = 30;
  String? _generatedCode;

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

  void _generate() {
    final deviceId = _deviceIdCtrl.text.trim();
    if (deviceId.isEmpty) {
      Fluttertoast.showToast(
        msg: 'أدخل معرّف جهاز العميل أولاً',
        backgroundColor: AppColors.error,
        textColor: Colors.white,
      );
      return;
    }
    final code = SubscriptionService.generatePersonalizedCode(
      deviceId: deviceId,
      planCode: _selectedPlan,
      days: _days,
    );
    setState(() => _generatedCode = code);
  }

  @override
  Widget build(BuildContext context) {
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
                color: AppColors.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.info.withValues(alpha: 0.2)),
              ),
              child: Text(
                'هذه الأداة للمطوّر فقط. اطلب من العميل نسخ "معرّف الجهاز" '
                'من شاشة تفعيل الاشتراك لديه وأرسله لك، ثم أدخله هنا لتوليد '
                'كود يعمل حصرياً على جهازه.',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.7,
                ),
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
                    final data =
                        await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      _deviceIdCtrl.text = data!.text!.trim().toUpperCase();
                      setState(() {});
                    }
                  },
                ),
              ),
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
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text('توليد الكود',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              ),
            ),
            if (_generatedCode != null) ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Text('الكود المُولَّد',
                        style: GoogleFonts.cairo(
                            fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    Text(
                      _generatedCode!,
                      textDirection: TextDirection.ltr,
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: _generatedCode!));
                        Fluttertoast.showToast(
                          msg: 'تم نسخ الكود ✅',
                          backgroundColor: AppColors.success,
                          textColor: Colors.white,
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: Text('نسخ الكود', style: GoogleFonts.cairo()),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
