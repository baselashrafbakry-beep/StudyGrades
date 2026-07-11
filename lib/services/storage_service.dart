import 'dart:async';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pending_sync.dart';
import '../utils/error_handler.dart';
import 'secure_hive_service.dart';

/// Local storage service using Hive (document) + SharedPreferences (key-value)
class StorageService {
  static const String pendingBoxName = 'pending_grades_box';
  static const String settingsBoxName = 'settings_box';
  static const String classroomCacheBox = 'classroom_cache_box';

  /// حد أقصى للقائمة المعلقة لمنع تراكمها بلا حد (1000 طالب = مؤمَّن)
  static const int _maxPendingItems = 1000;

  /// Cache لـ pendingCount لتجنب فك ترميز JSON في كل استدعاء (O(1) بدلاً من O(n))
  static int _cachedPendingCount = -1; // -1 = غير مُحدَّث بعد
  static String _activeOwnerKey = '';
  static Future<void> _pendingMutationBarrier = Future<void>.value();

  static Future<void> init() async {
    await Hive.initFlutter();
    await SecureHiveService.openBox(pendingBoxName);
    await SecureHiveService.openBox(settingsBoxName);
    await SecureHiveService.openBox(classroomCacheBox);
    // تهيئة الـ cache عند البدء
    _cachedPendingCount = getPendingSyncs().length;
  }

  // ============ Pending Syncs ============
  static Box get _pendingBox => Hive.box(pendingBoxName);
  static Box get _settingsBox => Hive.box(settingsBoxName);
  static Box get _cacheBox => Hive.box(classroomCacheBox);

  static String get activeOwnerKey => _activeOwnerKey;

  static void setActiveOwner(String? ownerKey) {
    final normalized = _normalizeOwnerKey(ownerKey);
    if (_activeOwnerKey == normalized) return;
    _activeOwnerKey = normalized;
    _cachedPendingCount = -1;
  }

  static String ownerScopedKey(String key, {String? ownerKey}) {
    final owner = _normalizeOwnerKey(ownerKey ?? _activeOwnerKey);
    return '${owner.isEmpty ? 'anonymous' : owner}|$key';
  }

  static Future<void> addPendingSync(
    PendingSync sync, {
    int maxItemsForOwner = _maxPendingItems,
  }) async {
    if (_activeOwnerKey.isEmpty) {
      throw StateError('Cannot queue grades without an authenticated owner.');
    }
    final ownerAtCall = _activeOwnerKey;
    final scopedSync = sync.withOwner(ownerAtCall);
    await _withPendingMutation(() async {
      final updated = PendingSyncQueue.upsert(
        current: _getAllPendingSyncs(),
        incoming: scopedSync,
        maxItemsForOwner: maxItemsForOwner.clamp(0, _maxPendingItems).toInt(),
      );
      await _writeAllPendingSyncs(updated);
    });
  }

  static List<PendingSync> getPendingSyncs() {
    final owner = _activeOwnerKey;
    return _getAllPendingSyncs()
        .where((s) => s.ownerKey == owner)
        .toList(growable: false);
  }

  static List<PendingSync> _getAllPendingSyncs() {
    if (!Hive.isBoxOpen(pendingBoxName)) return [];
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
    final ownerAtCall = _activeOwnerKey;
    await _withPendingMutation(() async {
      final retained = _getAllPendingSyncs()
          .where((s) => s.ownerKey != ownerAtCall)
          .toList(growable: false);
      await _writeAllPendingSyncs(retained);
    });
  }

  /// Replace the entire pending list (used when partially syncing).
  static Future<void> replacePendingSyncs(List<PendingSync> list) async {
    final ownerAtCall = _activeOwnerKey;
    final scoped = list
        .map((s) => s.ownerKey == ownerAtCall ? s : s.withOwner(ownerAtCall))
        .toList(growable: false);
    await _withPendingMutation(() async {
      final retained = _getAllPendingSyncs()
          .where((s) => s.ownerKey != ownerAtCall)
          .toList(growable: true);
      await _writeAllPendingSyncs([...retained, ...scoped]);
    });
  }

  static Future<void> removePendingForTarget(PendingSync sync) async {
    final scoped = sync.ownerKey.isEmpty
        ? sync.withOwner(_activeOwnerKey)
        : sync;
    await removeDeliveredPending([scoped]);
  }

  static Future<void> removeDeliveredPending(
    Iterable<PendingSync> delivered,
  ) async {
    final deliveredSnapshot = delivered.toList(growable: false);
    if (deliveredSnapshot.isEmpty) return;
    await _withPendingMutation(() async {
      final remaining = PendingSyncQueue.removeDelivered(
        current: _getAllPendingSyncs(),
        delivered: deliveredSnapshot,
      );
      await _writeAllPendingSyncs(remaining);
    });
  }

  /// O(1) — يُرجع من الـ cache مباشرةً دون فك ترميز JSON
  static int get pendingCount {
    if (!Hive.isBoxOpen(pendingBoxName)) return 0;
    if (_cachedPendingCount < 0) {
      // lazy init إذا لم تُستدعَ init() بعد
      _cachedPendingCount = getPendingSyncs().length;
    }
    return _cachedPendingCount;
  }

  static Future<void> _writeAllPendingSyncs(List<PendingSync> list) async {
    if (list.isEmpty) {
      await _pendingBox.delete('list');
    } else {
      await _pendingBox.put(
        'list',
        jsonEncode(list.map((e) => e.toJson()).toList()),
      );
    }
    _cachedPendingCount = list
        .where((sync) => sync.ownerKey == _activeOwnerKey)
        .length;
  }

  static Future<T> _withPendingMutation<T>(
    Future<T> Function() mutation,
  ) async {
    final previous = _pendingMutationBarrier;
    final release = Completer<void>();
    _pendingMutationBarrier = release.future;
    await previous;
    try {
      return await mutation();
    } finally {
      release.complete();
    }
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
  static Future<void> cacheClassroom(
    String key,
    Map<String, dynamic> data,
  ) async {
    final owner = _activeOwnerKey;
    final scopedData = Map<String, dynamic>.from(data)..['_owner_key'] = owner;
    await _cacheBox.put(ownerScopedKey(key), jsonEncode(scopedData));
  }

  static Map<String, dynamic>? getCachedClassroom(String key) {
    final raw = _cacheBox.get(ownerScopedKey(key)) as String?;
    if (raw == null) return null;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(raw));
      if ((data['_owner_key']?.toString() ?? '') != _activeOwnerKey) {
        return null;
      }
      data.remove('_owner_key');
      return data;
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'StorageService.getCachedClassroom');
      return null;
    }
  }

  static String _normalizeOwnerKey(String? ownerKey) {
    return (ownerKey ?? '').trim().toLowerCase();
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
