import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../screens/subscription_screen.dart';

/// حوار موحّد "ميزة/حد مدفوع" — يُستخدم عبر التطبيق بالكامل (تصدير Excel،
/// لوحة التحليلات، حدود عدد الطلاب/الفصول...) لضمان تجربة مستخدم متسقة
/// عند فرض قيود الاشتراك، بدلاً من تكرار نفس كود الحوار في كل شاشة.
class UpgradeRequiredDialog {
  UpgradeRequiredDialog._();

  static Future<void> show(
    BuildContext context, {
    required String featureNameAr,
    required String requiredPlanAr,
    IconData icon = Icons.workspace_premium_rounded,
    String? customMessage,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.warning, size: 34),
              ),
              const SizedBox(height: 14),
              Text(
                'ميزة مدفوعة',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                customMessage ??
                    'خاصية "$featureNameAr" متاحة فقط لباقة $requiredPlanAr'
                        ' فأعلى.\nيمكنك الترقية الآن للاستفادة من هذه الميزة'
                        ' وميزات أخرى متقدمة.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('لاحقاً', style: GoogleFonts.cairo()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SubscriptionScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.workspace_premium_rounded,
                          size: 18),
                      label: Text(
                        'ترقية الباقة',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
