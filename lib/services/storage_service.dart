import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pending_sync.dart';

/// Local storage service using Hive (document) + SharedPreferences (key-value)
class StorageService {
  static const String pendingBoxName = 'pending_grades_box';
  static const String settingsBoxName = 'settings_box';
  static const String classroomCacheBox = 'classroom_cache_box';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(pendingBoxName);
    await Hive.openBox(settingsBoxName);
    await Hive.openBox(classroomCacheBox);
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
    await _pendingBox.put(
      'list',
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  static List<PendingSync> getPendingSyncs() {
    final raw = _pendingBox.get('list') as String?;
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => PendingSync.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clearPendingSyncs() async {
    await _pendingBox.delete('list');
  }

  /// Replace the entire pending list (used when partially syncing).
  static Future<void> replacePendingSyncs(List<PendingSync> list) async {
    if (list.isEmpty) {
      await _pendingBox.delete('list');
      return;
    }
    await _pendingBox.put(
      'list',
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  static int get pendingCount => getPendingSyncs().length;

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
    } catch (_) {
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
