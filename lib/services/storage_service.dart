import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pending_sync.dart';
import '../utils/error_handler.dart';

/// Local storage service using Hive (document) + SharedPreferences (key-value)
class StorageService {
  static const String pendingBoxName = 'pending_grades_box';
  static const String settingsBoxName = 'settings_box';
  static const String classroomCacheBox = 'classroom_cache_box';

  /// حد أقصى للقائمة المعلقة لمنع تراكمها بلا حد (1000 طالب = مؤمَّن)
  static const int _maxPendingItems = 1000;

  /// Cache لـ pendingCount لتجنب فك ترميز JSON في كل استدعاء (O(1) بدلاً من O(n))
  static int _cachedPendingCount = -1; // -1 = غير مُحدَّث بعد

  static Future<void> init() async {
    // لا نستدعي Hive.initFlutter() مرة ثانية — تمت في main.dart
    // نفتح الصناديق فقط إذا لم تكن مفتوحة بالفعل
    if (!Hive.isBoxOpen(pendingBoxName)) {
      await Hive.openBox(pendingBoxName);
    }
    if (!Hive.isBoxOpen(settingsBoxName)) {
      await Hive.openBox(settingsBoxName);
    }
    if (!Hive.isBoxOpen(classroomCacheBox)) {
      await Hive.openBox(classroomCacheBox);
    }
    // تهيئة الـ cache عند البدء
    _cachedPendingCount = getPendingSyncs().length;
  }

  // ============ Pending Syncs ============
  static Box get _pendingBox => Hive.box(pendingBoxName);
  static Box get _settingsBox => Hive.box(settingsBoxName);
  static Box get _cacheBox => Hive.box(classroomCacheBox);

  static Future<void> addPendingSync(PendingSync sync) async {
    final list = getPendingSyncs();
    // Replace existing entry for same student to avoid duplicate stale data
    list.removeWhere(
      (s) => s.studentId == sync.studentId && s.subject == sync.subject,
    );
    list.add(sync);

    // تطبيق الحد الأقصى لمنع التراكم اللانهائي
    final trimmed = list.length > _maxPendingItems
        ? list.sublist(list.length - _maxPendingItems)
        : list;

    await _pendingBox.put(
      'list',
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
    _cachedPendingCount = trimmed.length; // تحديث الـ cache
  }

  static List<PendingSync> getPendingSyncs() {
    final raw = _pendingBox.get('list') as String?;
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => PendingSync.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'StorageService.getPendingSyncs');
      return [];
    }
  }

  static Future<void> clearPendingSyncs() async {
    await _pendingBox.delete('list');
    _cachedPendingCount = 0; // تحديث الـ cache
  }

  /// يمسح كل البيانات المحلية المؤقتة: المزامنة المعلقة + كاش الفصول +
  /// الإعدادات المحلية (auto_sync, haptic_feedback, use_server_speech...).
  /// يُستخدم في "الإعدادات > مسح البيانات المخزنة" حيث يُعلَم المستخدم
  /// صراحةً أن العملية ستحذف "الإعدادات المحلية" أيضاً وليس فقط المعلقات.
  /// ملاحظة: لا يمسح صناديق الأدمن (admin_users_box/admin_settings_box/
  /// admin_activity_box) ولا بيانات المصادقة (JWT tokens في SharedPreferences)
  /// لتجنّب تسجيل خروج المستخدم أو فقدان صلاحيات الإدارة عن طريق الخطأ.
  static Future<void> clearAllLocalData() async {
    await _pendingBox.clear();
    await _cacheBox.clear();
    await _settingsBox.clear();
    _cachedPendingCount = 0;
  }

  /// Replace the entire pending list (used when partially syncing).
  static Future<void> replacePendingSyncs(List<PendingSync> list) async {
    if (list.isEmpty) {
      await _pendingBox.delete('list');
      _cachedPendingCount = 0;
      return;
    }
    await _pendingBox.put(
      'list',
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
    _cachedPendingCount = list.length; // تحديث الـ cache
  }

  /// O(1) — يُرجع من الـ cache مباشرةً دون فك ترميز JSON
  static int get pendingCount {
    if (_cachedPendingCount < 0) {
      // lazy init إذا لم تُستدعَ init() بعد
      _cachedPendingCount = getPendingSyncs().length;
    }
    return _cachedPendingCount;
  }

  // ============ Settings ============
  static Future<void> setSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }

  static T? getSetting<T>(String key, {T? defaultValue}) {
    final v = _settingsBox.get(key);
    if (v == null) return defaultValue;
    if (v is T) return v;
    return defaultValue;
  }

  // ============ Classroom Cache ============
  static Future<void> cacheClassroom(String key, Map<String, dynamic> data) async {
    await _cacheBox.put(key, jsonEncode(data));
  }

  static Map<String, dynamic>? getCachedClassroom(String key) {
    final raw = _cacheBox.get(key) as String?;
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'StorageService.getCachedClassroom');
      return null;
    }
  }

  // ============ SharedPreferences Helpers ============
  static Future<bool> hasSeenIntro() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('seen_intro') ?? false;
  }

  static Future<void> markIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_intro', true);
  }
}
