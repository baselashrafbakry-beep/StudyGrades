// نموذج نظام الاشتراكات - StudyGrades
// المطور: م. باسل أشرف

enum SubscriptionPlan {
  free, // مجاني - محدود
  basic, // أساسي - شهري
  pro, // احترافي - شهري
  school, // مدرسة - سنوي
}

class SubscriptionPlanInfo {
  final SubscriptionPlan plan;
  final String nameAr;
  final String nameEn;
  final String description;
  final double priceMonthly; // بالجنيه المصري
  final double priceYearly; // بالجنيه المصري
  final int maxTeachers; // -1 = غير محدود
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
  // ==========================================================================
  // 🆕 حقل "حد الأجهزة" (Device Limit) — أُضيف بناءً على ملف الإعداد التجاري
  // الرسمي (StudyGrades-commercial.env): STARTER_DEVICE_LIMIT=1،
  // PROFESSIONAL_DEVICE_LIMIT=2. هذا الحقل يمثّل عدد الأجهزة المسموح
  // للمشترك الفردي (Starter/Professional) استخدام اشتراكه عليها في آنٍ واحد.
  //
  // ⚠️ ملاحظة معمارية هامة وصادقة (Honest Limitation): نظام التفعيل الحالي
  // بالكامل offline ويعمل عبر تراخيص RSA-2048 موقَّعة *لكل جهاز على حدة*
  // (انظر SubscriptionService._tryParsePersonalizedCode) — لا يوجد أي مفهوم
  // "حساب عميل" منفصل عن "معرّف الجهاز" يمكن للتطبيق التحقق منه محلياً لعدّ
  // كم جهازاً يستخدمه هذا العميل فعلياً. لذلك:
  //   • خطة Starter (حد=1): محقَّقة بطبيعة النظام تلقائياً، لأن كل كود
  //     SGV2-... مربوط بجهاز واحد فقط عند توليده.
  //   • خطة Professional (حد=2): تُطبَّق حالياً على مستوى *سياسة التوليد*
  //     الخارجية (يُصدِر المطوّر عبر license_generator_screen/
  //     generate_license.py كودين منفصلين، كل منهما لجهاز مختلف، لنفس
  //     العميل عند الطلب) — وليس عبر فحص برمجي داخل هذا التطبيق.
  //   • أي إنفاذ مركزي حقيقي (مثال: منع تفعيل جهاز ثالث تلقائياً) يتطلب
  //     نظام حسابات على الباك-إند (Django) لا وجود له في هذا المستودع بعد.
  // هذا الحقل هنا إذن هو "شفافية للمستخدم في واجهة الأسعار" بشكل صادق ودقيق،
  // وليس ادّعاءً بوجود إنفاذ تقني كامل غير موجود فعلياً.
  // ==========================================================================
  final int maxDevices; // -1 = غير محدود (لا ينطبق على خطة المدرسة تحديداً)

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
    required this.maxDevices,
  });

  bool get isUnlimitedTeachers => maxTeachers == -1;
  bool get isUnlimitedStudents => maxStudentsPerClass == -1;
  bool get isUnlimitedClasses => maxClassesPerTeacher == -1;
  bool get isUnlimitedDevices => maxDevices == -1;

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
///
/// ⚠️⚠️⚠️ مصدر الحقيقة الوحيد للأسعار (Single Source of Truth) ⚠️⚠️⚠️
/// جميع أسعار وحدود هذا الملف مأخوذة **حصراً وحرفياً** من ملف الإعداد
/// التجاري الرسمي المُقدَّم من المطوّر/صاحب المنتج:
///   /home/user/secrets/StudyGrades-commercial.env
/// (تم نقله خارج مستودع git لحماية أسرار الدفع الحية المرفقة فيه، لكن
/// القيم غير السرّية — الأسعار والحدود — منقولة هنا حرفياً بأمر صريح من
/// صاحب المنتج: "خذ الاسعار فقط من الملف المرفق").
///
/// أي تعديل مستقبلي على الأسعار يجب أن يأتي فقط من نسخة محدَّثة رسمياً من
/// ذلك الملف، وليس تخميناً أو قيمة افتراضية يضعها أي مطوّر لاحقاً.
///
/// جدول المطابقة (env → enum الحالي في الكود، بدون تغيير اسم الـ enum
/// نفسه تفادياً لكسر مزامنة السيرفر القائمة على .name — انظر التوثيق
/// الكامل في subscription_service.dart):
///   STARTER_MONTHLY_PRICE=30      / STARTER_ANNUAL_PRICE=300      → basic
///   PROFESSIONAL_MONTHLY_PRICE=60 / PROFESSIONAL_ANNUAL_PRICE=600 → pro
///   SCHOOL_MONTHLY_PRICE=700      / SCHOOL_ANNUAL_PRICE=8200      → school
///   STARTER_DEVICE_LIMIT=1        → basic.maxDevices
///   PROFESSIONAL_DEVICE_LIMIT=2   → pro.maxDevices
///   SCHOOL_SEAT_LIMIT=25          → school.maxTeachers (كان -1/غير محدود،
///                                   أصبح حداً ثابتاً 25 بأمر الملف الرسمي)
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
      maxDevices: 1,
    ),
    // Starter — 30 جنيه/شهر، 300 جنيه/سنة، حد جهاز واحد (STARTER_DEVICE_LIMIT=1)
    SubscriptionPlanInfo(
      plan: SubscriptionPlan.basic,
      nameAr: 'ستارتر',
      nameEn: 'Starter',
      description: 'للمعلم الفرد مع ميزات متقدمة',
      priceMonthly: 30,
      priceYearly: 300,
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
      maxDevices: 1,
    ),
    // Professional — 60 جنيه/شهر، 600 جنيه/سنة، حد جهازين (PROFESSIONAL_DEVICE_LIMIT=2)
    SubscriptionPlanInfo(
      plan: SubscriptionPlan.pro,
      nameAr: 'احترافي',
      nameEn: 'Professional',
      description: 'للمعلم المحترف بجميع الميزات',
      priceMonthly: 60,
      priceYearly: 600,
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
      maxDevices: 2,
    ),
    // School — 700 جنيه/شهر، 8200 جنيه/سنة، حد 25 مقعد معلم (SCHOOL_SEAT_LIMIT=25)
    SubscriptionPlanInfo(
      plan: SubscriptionPlan.school,
      nameAr: 'مدرسة',
      nameEn: 'School',
      description: 'للمدارس والمؤسسات التعليمية',
      priceMonthly: 700,
      priceYearly: 8200,
      maxTeachers: 25,
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
      maxDevices:
          -1, // غير محدود على مستوى الجهاز؛ الضبط الفعلي عبر مقاعد المعلمين (25)
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
  bool get isExpired =>
      expiryDate != null && DateTime.now().isAfter(expiryDate!);
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
    // 🔴 عطل تم اكتشافه وإصلاحه هنا (daysRemaining Semantic Collision):
    // كان الحد الأدنى للـ clamp هو -1 رغم أن هذا التعليق نفسه يوثّق نية
    // مخالفة ("يجب أن يكون 0 وليس سالباً"). القيمة -1 محجوزة حصرياً في
    // UserSubscription.free() للدلالة على "اشتراك مستمر بلا تاريخ انتهاء
    // إطلاقاً". لو وصل هذا الفرع (expiry != null) بتاريخ انتهاء في
    // الماضي (اشتراك مدفوع منتهي فعلياً)، كان clamp(-1, 9999) يُعيد -1
    // أيضاً — أي نفس قيمة "الاستمرارية بلا نهاية"! أي كود مستقبلي يتحقق
    // من daysRemaining == -1 مباشرة (بدل الاعتماد على isExpired/expiryDate)
    // كان سيُفسِّر خطأً اشتراكاً مدفوعاً منتهياً منذ أيام على أنه "مجاني
    // مستمر بلا حدود". الإصلاح: الحد الأدنى الصحيح لحالة "هناك تاريخ
    // انتهاء محدَّد" هو 0 (منتهي/ينتهي اليوم)، وتبقى -1 محجوزة فقط لحالة
    // "لا يوجد تاريخ انتهاء إطلاقاً" (expiry == null).
    final days = expiry != null
        ? expiry.difference(DateTime.now()).inDays.clamp(0, 9999)
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
