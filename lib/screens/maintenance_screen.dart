import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/admin_service.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';

/// شاشة الصيانة — تُعرض لجميع المستخدمين (باستثناء المطور) عندما يقوم
/// المطور بتفعيل "وضع الصيانة" من لوحة التحكم في إعدادات النظام.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<
        ThemeProvider>(); // يضمن إعادة البناء فوراً عند تبديل الوضع الليلي/الفاتح
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.engineering_rounded,
                      size: 56, color: AppColors.warning),
                ),
                const SizedBox(height: 24),
                Text(
                  'التطبيق في وضع الصيانة',
                  style: GoogleFonts.cairo(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'نقوم حالياً بإجراء بعض التحديثات على النظام.\n'
                  'يرجى المحاولة مرة أخرى بعد قليل.',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.7,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                        const ClipboardData(text: AdminService.developerPhone));
                    Fluttertoast.showToast(
                      msg: 'تم نسخ رقم واتساب المطوّر ✅',
                      backgroundColor: AppColors.success,
                      textColor: Colors.white,
                    );
                  },
                  icon: const Icon(Icons.phone_in_talk_rounded),
                  label: Text(
                    'نسخ رقم واتساب المطوّر: ${AdminService.developerPhone}',
                    style: GoogleFonts.cairo(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
