/// Commercial subscription and entitlement model for StudyGrades.
///
/// The mobile app does not process payments locally. It consumes subscription
/// fields returned by the backend and enforces the matching product limits.
class SubscriptionPlan {
  static const String legacy = 'legacy';
  static const String trial = 'trial';
  static const String starter = 'starter';
  static const String professional = 'professional';
  static const String school = 'school';
  static const String enterprise = 'enterprise';

  static const List<String> all = [
    legacy,
    trial,
    starter,
    professional,
    school,
    enterprise,
  ];

  static const List<String> commercial = [
    trial,
    starter,
    professional,
    school,
    enterprise,
  ];

  static String normalize(dynamic value) {
    final raw = value?.toString().trim().toLowerCase().replaceAll('-', '_');
    if (raw == null || raw.isEmpty) return legacy;
    switch (raw) {
      case 'free_trial':
      case 'demo':
        return trial;
      case 'basic':
      case 'teacher':
        return starter;
      case 'pro':
      case 'paid':
        return professional;
      case 'business':
      case 'academy':
        return school;
      case 'unlimited':
        return enterprise;
      default:
        return all.contains(raw) ? raw : legacy;
    }
  }

  static String label(String plan) {
    switch (normalize(plan)) {
      case trial:
        return 'تجربة';
      case starter:
        return 'Starter';
      case professional:
        return 'Professional';
      case school:
        return 'School';
      case enterprise:
        return 'Enterprise';
      case legacy:
      default:
        return 'Legacy';
    }
  }
}

class SubscriptionStatus {
  static const String none = 'none';
  static const String trialing = 'trialing';
  static const String active = 'active';
  static const String pastDue = 'past_due';
  static const String canceled = 'canceled';
  static const String expired = 'expired';

  static const List<String> all = [
    none,
    trialing,
    active,
    pastDue,
    canceled,
    expired,
  ];

  static String normalize(dynamic value) {
    final raw = value?.toString().trim().toLowerCase().replaceAll('-', '_');
    if (raw == null || raw.isEmpty) return none;
    switch (raw) {
      case 'trial':
      case 'on_trial':
        return trialing;
      case 'paid':
      case 'enabled':
        return active;
      case 'pastdue':
      case 'payment_failed':
        return pastDue;
      case 'cancelled':
        return canceled;
      default:
        return all.contains(raw) ? raw : none;
    }
  }

  static String label(String status) {
    switch (normalize(status)) {
      case trialing:
        return 'تجربة نشطة';
      case active:
        return 'نشط';
      case pastDue:
        return 'متأخر الدفع';
      case canceled:
        return 'ملغي';
      case expired:
        return 'منتهي';
      case none:
      default:
        return 'غير مفعّل';
    }
  }
}

class PlanLimits {
  final int maxStudentsPerClass;
  final int maxPendingSync;
  final int maxDevices;
  final int maxSeats;
  final int trialDays;
  final bool serverTranscription;
  final bool exportReports;
  final bool advancedAnalytics;
  final bool userManagement;

  const PlanLimits({
    required this.maxStudentsPerClass,
    required this.maxPendingSync,
    required this.maxDevices,
    required this.maxSeats,
    required this.trialDays,
    required this.serverTranscription,
    required this.exportReports,
    required this.advancedAnalytics,
    required this.userManagement,
  });

  factory PlanLimits.forPlan(String plan) {
    switch (SubscriptionPlan.normalize(plan)) {
      case SubscriptionPlan.trial:
        return const PlanLimits(
          maxStudentsPerClass: 25,
          maxPendingSync: 30,
          maxDevices: 1,
          maxSeats: 1,
          trialDays: 14,
          serverTranscription: false,
          exportReports: false,
          advancedAnalytics: false,
          userManagement: false,
        );
      case SubscriptionPlan.starter:
        return const PlanLimits(
          maxStudentsPerClass: 60,
          maxPendingSync: 120,
          maxDevices: 1,
          maxSeats: 1,
          trialDays: 0,
          serverTranscription: false,
          exportReports: true,
          advancedAnalytics: false,
          userManagement: false,
        );
      case SubscriptionPlan.professional:
        return const PlanLimits(
          maxStudentsPerClass: 120,
          maxPendingSync: 300,
          maxDevices: 3,
          maxSeats: 1,
          trialDays: 0,
          serverTranscription: true,
          exportReports: true,
          advancedAnalytics: true,
          userManagement: false,
        );
      case SubscriptionPlan.school:
        return const PlanLimits(
          maxStudentsPerClass: 500,
          maxPendingSync: 1000,
          maxDevices: 20,
          maxSeats: 25,
          trialDays: 0,
          serverTranscription: true,
          exportReports: true,
          advancedAnalytics: true,
          userManagement: true,
        );
      case SubscriptionPlan.enterprise:
      case SubscriptionPlan.legacy:
      default:
        return const PlanLimits(
          maxStudentsPerClass: 0,
          maxPendingSync: 1000,
          maxDevices: 0,
          maxSeats: 0,
          trialDays: 0,
          serverTranscription: true,
          exportReports: true,
          advancedAnalytics: true,
          userManagement: true,
        );
    }
  }

  factory PlanLimits.fromJson(
    Map<String, dynamic>? json, {
    required PlanLimits fallback,
  }) {
    if (json == null) return fallback;
    return PlanLimits(
      maxStudentsPerClass:
          _parseInt(
            json['max_students_per_class'] ?? json['maxStudentsPerClass'],
          ) ??
          fallback.maxStudentsPerClass,
      maxPendingSync:
          _parseInt(json['max_pending_sync'] ?? json['maxPendingSync']) ??
          fallback.maxPendingSync,
      maxDevices:
          _parseInt(json['max_devices'] ?? json['maxDevices']) ??
          fallback.maxDevices,
      maxSeats:
          _parseInt(json['max_seats'] ?? json['maxSeats']) ?? fallback.maxSeats,
      trialDays:
          _parseInt(json['trial_days'] ?? json['trialDays']) ??
          fallback.trialDays,
      serverTranscription:
          _parseBool(
            json['server_transcription'] ?? json['serverTranscription'],
          ) ??
          fallback.serverTranscription,
      exportReports:
          _parseBool(json['export_reports'] ?? json['exportReports']) ??
          fallback.exportReports,
      advancedAnalytics:
          _parseBool(json['advanced_analytics'] ?? json['advancedAnalytics']) ??
          fallback.advancedAnalytics,
      userManagement:
          _parseBool(json['user_management'] ?? json['userManagement']) ??
          fallback.userManagement,
    );
  }

  Map<String, dynamic> toJson() => {
    'max_students_per_class': maxStudentsPerClass,
    'max_pending_sync': maxPendingSync,
    'max_devices': maxDevices,
    'max_seats': maxSeats,
    'trial_days': trialDays,
    'server_transcription': serverTranscription,
    'export_reports': exportReports,
    'advanced_analytics': advancedAnalytics,
    'user_management': userManagement,
  };

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (['true', '1', 'yes', 'y'].contains(text)) return true;
    if (['false', '0', 'no', 'n'].contains(text)) return false;
    return null;
  }
}

class Subscription {
  final String plan;
  final String status;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final bool lifetime;
  final bool deviceLimitReached;
  final bool seatLimitReached;
  final PlanLimits limits;

  Subscription({
    required String plan,
    required String status,
    this.startsAt,
    this.expiresAt,
    this.lifetime = false,
    this.deviceLimitReached = false,
    this.seatLimitReached = false,
    PlanLimits? limits,
  }) : plan = SubscriptionPlan.normalize(plan),
       status = SubscriptionStatus.normalize(status),
       limits = limits ?? PlanLimits.forPlan(SubscriptionPlan.normalize(plan));

  factory Subscription.legacyActive() {
    return Subscription(
      plan: SubscriptionPlan.legacy,
      status: SubscriptionStatus.active,
      lifetime: true,
    );
  }

  factory Subscription.developerLifetime() {
    return Subscription(
      plan: SubscriptionPlan.enterprise,
      status: SubscriptionStatus.active,
      lifetime: true,
    );
  }

  factory Subscription.unlicensed() {
    return Subscription(
      plan: SubscriptionPlan.trial,
      status: SubscriptionStatus.none,
    );
  }

  factory Subscription.fromJson(dynamic raw, {String? fallbackPlan}) {
    if (raw is! Map) {
      return Subscription.unlicensed();
    }
    final json = Map<String, dynamic>.from(raw);
    final plan = SubscriptionPlan.normalize(
      json['plan'] ??
          json['subscription_plan'] ??
          json['billing_plan'] ??
          fallbackPlan,
    );
    final defaultLimits = PlanLimits.forPlan(plan);
    final limitsRaw = json['limits'];
    final limits = PlanLimits.fromJson(
      limitsRaw is Map ? Map<String, dynamic>.from(limitsRaw) : null,
      fallback: defaultLimits,
    );
    return Subscription(
      plan: plan,
      status: json['status'] ?? json['subscription_status'],
      startsAt: _parseDate(json['starts_at'] ?? json['started_at']),
      expiresAt: _parseDate(
        json['expires_at'] ??
            json['subscription_expires_at'] ??
            json['current_period_end'] ??
            json['trial_ends_at'],
      ),
      lifetime: _parseBool(json['lifetime'] ?? json['is_lifetime']) ?? false,
      deviceLimitReached:
          _parseBool(
            json['device_limit_reached'] ?? json['deviceLimitReached'],
          ) ??
          false,
      seatLimitReached:
          _parseBool(json['seat_limit_reached'] ?? json['seatLimitReached']) ??
          false,
      limits: limits,
    );
  }

  bool get isExpiredByDate {
    final expiry = expiresAt;
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry);
  }

  bool get isUsable =>
      (lifetime ||
          ((status == SubscriptionStatus.active ||
                  status == SubscriptionStatus.trialing) &&
              !isExpiredByDate)) &&
      !deviceLimitReached &&
      !seatLimitReached;

  bool get needsPayment =>
      status == SubscriptionStatus.pastDue ||
      status == SubscriptionStatus.canceled ||
      status == SubscriptionStatus.expired ||
      isExpiredByDate ||
      status == SubscriptionStatus.none;

  bool get canUseServerTranscription => isUsable && limits.serverTranscription;

  bool get canExportReports => isUsable && limits.exportReports;

  bool get canUseAdvancedAnalytics => isUsable && limits.advancedAnalytics;

  bool get canManageCommercialUsers => isUsable && limits.userManagement;

  bool canUseStudentCount(int count) {
    return isUsable &&
        (limits.maxStudentsPerClass <= 0 ||
            count <= limits.maxStudentsPerClass);
  }

  bool canQueueMorePending(int pendingCount) {
    return isUsable &&
        limits.maxPendingSync > 0 &&
        pendingCount < limits.maxPendingSync;
  }

  String get planLabel => SubscriptionPlan.label(plan);

  String get statusLabel {
    if (isExpiredByDate && !lifetime) return 'منتهي';
    return SubscriptionStatus.label(status);
  }

  String get expiryLabel {
    if (lifetime) return 'مدى الحياة';
    final expiry = expiresAt;
    if (expiry == null) return 'بدون تاريخ انتهاء';
    final day = expiry.day.toString().padLeft(2, '0');
    final month = expiry.month.toString().padLeft(2, '0');
    return '$day/$month/${expiry.year}';
  }

  String blockedMessage(String featureName) {
    if (!isUsable) {
      return 'لا يمكن استخدام $featureName لأن الاشتراك غير نشط أو منتهي.';
    }
    return 'ميزة $featureName غير متاحة في خطة $planLabel الحالية.';
  }

  Map<String, dynamic> toJson() => {
    'plan': plan,
    'status': status,
    'starts_at': startsAt?.toIso8601String(),
    'expires_at': expiresAt?.toIso8601String(),
    'lifetime': lifetime,
    'device_limit_reached': deviceLimitReached,
    'seat_limit_reached': seatLimitReached,
    'limits': limits.toJson(),
  };

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (['true', '1', 'yes', 'y'].contains(text)) return true;
    if (['false', '0', 'no', 'n'].contains(text)) return false;
    return null;
  }
}
