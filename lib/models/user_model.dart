import 'subscription_model.dart';

/// أدوار المستخدمين في النظام
class UserRole {
  static const String developer = 'developer'; // مطور النظام (باسل أشرف)
  static const String admin = 'admin'; // مدير
  static const String manager = 'manager'; // مشرف/مدير مدرسة
  static const String teacher = 'teacher'; // معلم (الافتراضي)

  static const List<String> all = [developer, admin, manager, teacher];

  /// تسمية الدور بالعربية
  static String label(String role) {
    switch (role) {
      case developer:
        return 'المطوّر';
      case admin:
        return 'مدير النظام';
      case manager:
        return 'مشرف';
      case teacher:
        return 'معلم';
      default:
        return 'مستخدم';
    }
  }

  /// أيقونة الدور
  static String icon(String role) {
    switch (role) {
      case developer:
        return '👨‍💻';
      case admin:
        return '🛡️';
      case manager:
        return '🎓';
      case teacher:
        return '📚';
      default:
        return '👤';
    }
  }

  /// مستوى الصلاحية (الأعلى = صلاحيات أكثر)
  static int level(String role) {
    switch (role) {
      case developer:
        return 100;
      case admin:
        return 80;
      case manager:
        return 50;
      case teacher:
        return 10;
      default:
        return 0;
    }
  }
}

/// نموذج المستخدم
class User {
  final int id;
  final String username;
  final String email;
  final String role;
  final String fullName;
  final String? phone;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? lastLogin;
  final String? avatar;
  final Subscription subscription;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.fullName = '',
    this.phone,
    this.isActive = true,
    this.createdAt,
    this.lastLogin,
    this.avatar,
    Subscription? subscription,
  }) : subscription = subscription ?? Subscription.unlicensed();

  // ----- صلاحيات سريعة -----
  bool get isDeveloper => role == UserRole.developer;
  bool get isAdmin => role == UserRole.admin;
  bool get isManager => role == UserRole.manager;
  bool get isTeacher => role == UserRole.teacher;

  /// هل لديه صلاحية الوصول لـ Admin Panel
  bool get canAccessAdminPanel =>
      (role == UserRole.developer || role == UserRole.admin) &&
      subscription.isUsable;

  /// هل لديه صلاحية إدارة المستخدمين
  bool get canManageUsers =>
      (role == UserRole.developer || role == UserRole.admin) &&
      subscription.canManageCommercialUsers;

  /// هل لديه صلاحية الوصول لإحصاءات النظام الكاملة
  bool get canViewSystemStats => role == UserRole.developer;

  /// هل لديه صلاحية تعديل إعدادات النظام
  bool get canEditSystemSettings => role == UserRole.developer;

  bool get hasActiveSubscription => subscription.isUsable;

  /// هل بإمكانه تعديل/حذف مستخدم آخر بناءً على دوره
  bool canModifyUser(User other) {
    if (id == other.id) return false; // لا يعدّل نفسه
    return UserRole.level(role) > UserRole.level(other.role);
  }

  String get displayName => fullName.isNotEmpty ? fullName : username;

  String get storageOwnerKey {
    final normalizedUsername = username.trim().toLowerCase();
    final stableId = id > 0 ? id.toString() : normalizedUsername;
    return 'user:$stableId:$normalizedUsername';
  }

  factory User.fromJson(Map<String, dynamic> json) {
    final parsedRole = _parseRole(json['role']);
    return User(
      id: _parseInt(json['id']) ?? 0,
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: parsedRole,
      fullName:
          json['full_name']?.toString() ?? json['fullName']?.toString() ?? '',
      phone: json['phone']?.toString(),
      isActive: _parseBool(json['is_active'] ?? json['isActive']) ?? true,
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
      lastLogin: _parseDate(json['last_login'] ?? json['lastLogin']),
      avatar: json['avatar']?.toString(),
      subscription: _parseSubscription(json, parsedRole),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'role': role,
    'full_name': fullName,
    'phone': phone,
    'is_active': isActive,
    'created_at': createdAt?.toIso8601String(),
    'last_login': lastLogin?.toIso8601String(),
    'avatar': avatar,
    'subscription': subscription.toJson(),
  };

  User copyWith({
    int? id,
    String? username,
    String? email,
    String? role,
    String? fullName,
    String? phone,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastLogin,
    String? avatar,
    Subscription? subscription,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      role: role ?? this.role,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      avatar: avatar ?? this.avatar,
      subscription: subscription ?? this.subscription,
    );
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    if (v is double) return v.toInt();
    return null;
  }

  static String _parseRole(dynamic v) {
    final role = v?.toString().trim().toLowerCase();
    if (role != null && UserRole.all.contains(role)) return role;
    return UserRole.teacher;
  }

  static bool? _parseBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final text = v.toString().trim().toLowerCase();
    if (['true', '1', 'yes', 'y'].contains(text)) return true;
    if (['false', '0', 'no', 'n'].contains(text)) return false;
    return null;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        // Date parsing failed - return null silently (validation only)
      }
    }
    return null;
  }

  static Subscription _parseSubscription(
    Map<String, dynamic> json,
    String role,
  ) {
    final raw = json['subscription'];
    if (raw is Map) {
      return Subscription.fromJson(Map<String, dynamic>.from(raw));
    }

    final topLevelPlan =
        json['subscription_plan'] ?? json['plan'] ?? json['billing_plan'];
    final topLevelStatus = json['subscription_status'];
    final topLevelExpiry =
        json['subscription_expires_at'] ??
        json['expires_at'] ??
        json['current_period_end'] ??
        json['trial_ends_at'];

    if (topLevelPlan != null ||
        topLevelStatus != null ||
        topLevelExpiry != null) {
      return Subscription.fromJson({
        'plan': topLevelPlan,
        'status': topLevelStatus,
        'expires_at': topLevelExpiry,
        'lifetime': json['lifetime'] ?? json['is_lifetime'],
        'device_limit_reached':
            json['device_limit_reached'] ?? json['deviceLimitReached'],
        'seat_limit_reached':
            json['seat_limit_reached'] ?? json['seatLimitReached'],
      });
    }

    if (role == UserRole.developer) {
      return Subscription.developerLifetime();
    }
    return Subscription.unlicensed();
  }
}
