// نموذج نظام الاشتراكات - Study Grades Voice
// المطور: م. باسل أشرف

enum SubscriptionPlan {
  free,       // مجاني - محدود
  basic,      // أساسي - شهري
  pro,        // احترافي - شهري
  school,     // مدرسة - سنوي
}

class SubscriptionPlanInfo {
  final SubscriptionPlan plan;
  final String nameAr;
  final String nameEn;
  final String description;
  final double priceMonthly; // بالجنيه المصري
  final double priceYearly;  // بالجنيه المصري
  final int maxTeachers;     // -1 = غير محدود
  final int maxStudentsPerClass;
  final int maxClassesPerTeacher;
  final bool voiceInput;
  final bool offlineSync;
  final bool analytics;
  final bool exportExcel;
  final bool exportCsv;
  final bool adminPanel;
  final bool prioritySupport;
  final String badge;
  final String colorHex;

  const SubscriptionPlanInfo({
    required this.plan,
    required this.nameAr,
    required this.nameEn,
    required this.description,
    required this.priceMonthly,
    required this.priceYearly,
    required this.maxTeachers,
    required this.maxStudentsPerClass,
    required this.maxClassesPerTeacher,
    required this.voiceInput,
    required this.offlineSync,
    required this.analytics,
    required this.exportExcel,
    required this.exportCsv,
    required this.adminPanel,
    required this.prioritySupport,
    required this.badge,
    required this.colorHex,
  });

  bool get isUnlimitedTeachers => maxTeachers == -1;
  bool get isUnlimitedStudents => maxStudentsPerClass == -1;
  bool get isUnlimitedClasses => maxClassesPerTeacher == -1;

  String get priceMonthlyFormatted {
    if (priceMonthly == 0) return 'مجاني';
    return '${priceMonthly.toInt()} جنيه/شهر';
  }

  String get priceYearlyFormatted {
    if (priceYearly == 0) return 'مجاني';
    return '${priceYearly.toInt()} جنيه/سنة';
  }

  double get yearlyDiscount {
    if (priceMonthly == 0) return 0;
    final fullYear = priceMonthly * 12;
    return ((fullYear - priceYearly) / fullYear) * 100;
  }
}

/// خطط الاشتراك المتاحة
class SubscriptionPlans {
  static const List<SubscriptionPlanInfo> all = [
    SubscriptionPlanInfo(
      plan: SubscriptionPlan.free,
      nameAr: 'مجاني',
      nameEn: 'Free',
      description: 'ابدأ مجاناً وجرب الميزات الأساسية',
      priceMonthly: 0,
      priceYearly: 0,
      maxTeachers: 1,
      maxStudentsPerClass: 30,
      maxClassesPerTeacher: 2,
      voiceInput: true,
      offlineSync: false,
      analytics: false,
      exportExcel: false,
      exportCsv: false,
      adminPanel: false,
      prioritySupport: false,
      badge: '🆓',
      colorHex: '#607D8B',
    ),
    SubscriptionPlanInfo(
      plan: SubscriptionPlan.basic,
      nameAr: 'أساسي',
      nameEn: 'Basic',
      description: 'للمعلم الفرد مع ميزات متقدمة',
      priceMonthly: 49,
      priceYearly: 449,
      maxTeachers: 1,
      maxStudentsPerClass: 50,
      maxClassesPerTeacher: 5,
      voiceInput: true,
      offlineSync: true,
      analytics: true,
      exportExcel: false,
      exportCsv: true,
      adminPanel: false,
      prioritySupport: false,
      badge: '⭐',
      colorHex: '#1976D2',
    ),
    SubscriptionPlanInfo(
      plan: SubscriptionPlan.pro,
      nameAr: 'احترافي',
      nameEn: 'Pro',
      description: 'للمعلم المحترف بجميع الميزات',
      priceMonthly: 99,
      priceYearly: 899,
      maxTeachers: 1,
      maxStudentsPerClass: -1,
      maxClassesPerTeacher: -1,
      voiceInput: true,
      offlineSync: true,
      analytics: true,
      exportExcel: true,
      exportCsv: true,
      adminPanel: false,
      prioritySupport: true,
      badge: '💎',
      colorHex: '#7B1FA2',
    ),
    SubscriptionPlanInfo(
      plan: SubscriptionPlan.school,
      nameAr: 'مدرسة',
      nameEn: 'School',
      description: 'للمدارس والمؤسسات التعليمية',
      priceMonthly: 0,
      priceYearly: 2999,
      maxTeachers: -1,
      maxStudentsPerClass: -1,
      maxClassesPerTeacher: -1,
      voiceInput: true,
      offlineSync: true,
      analytics: true,
      exportExcel: true,
      exportCsv: true,
      adminPanel: true,
      prioritySupport: true,
      badge: '🏫',
      colorHex: '#2E7D32',
    ),
  ];

  static SubscriptionPlanInfo getPlan(SubscriptionPlan plan) {
    return all.firstWhere((p) => p.plan == plan);
  }
}

/// حالة اشتراك المستخدم
class UserSubscription {
  final SubscriptionPlan plan;
  final DateTime? startDate;
  final DateTime? expiryDate;
  final bool isActive;
  final bool isTrial;
  final int daysRemaining;

  const UserSubscription({
    required this.plan,
    this.startDate,
    this.expiryDate,
    required this.isActive,
    this.isTrial = false,
    required this.daysRemaining,
  });

  factory UserSubscription.free() => const UserSubscription(
        plan: SubscriptionPlan.free,
        isActive: true,
        daysRemaining: -1, // مستمر
      );

  bool get isPaid => plan != SubscriptionPlan.free;
  bool get isExpired => expiryDate != null && DateTime.now().isAfter(expiryDate!);
  bool get isExpiringSoon => daysRemaining > 0 && daysRemaining <= 7;

  SubscriptionPlanInfo get planInfo => SubscriptionPlans.getPlan(plan);

  Map<String, dynamic> toJson() => {
        'plan': plan.name,
        'start_date': startDate?.toIso8601String(),
        'expiry_date': expiryDate?.toIso8601String(),
        'is_active': isActive,
        'is_trial': isTrial,
      };

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    final planName = json['plan']?.toString() ?? 'free';
    final plan = SubscriptionPlan.values.firstWhere(
      (p) => p.name == planName,
      orElse: () => SubscriptionPlan.free,
    );
    final expiry = json['expiry_date'] != null
        ? DateTime.tryParse(json['expiry_date'].toString())
        : null;
    // إصلاح: daysRemaining يجب أن يكون 0 عند الانتهاء وليس سالباً
    final days = expiry != null
        ? expiry.difference(DateTime.now()).inDays.clamp(-1, 9999)
        : -1;
    return UserSubscription(
      plan: plan,
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'].toString())
          : null,
      expiryDate: expiry,
      isActive: json['is_active'] as bool? ?? true,
      isTrial: json['is_trial'] as bool? ?? false,
      daysRemaining: days,
    );
  }
}
