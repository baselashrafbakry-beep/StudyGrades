import 'package:flutter/foundation.dart';
import '../models/student_model.dart';
import '../models/pending_sync.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../services/connectivity_service.dart';

/// Grading provider - manages classroom data, current student index, grade
/// updates, and online/offline synchronization. Includes proper error
/// reporting and automatic retry on connectivity restore.
class GradingProvider extends ChangeNotifier {
  ClassroomData? _classroom;
  int _currentIndex = 0;
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _error;
  String? _lastSyncMessage;

  // Live status
  bool _isOnline = true;
  int _pendingCount = 0;

  ClassroomData? get classroom => _classroom;
  List<Student> get students => _classroom?.students ?? [];
  List<GradeField> get fields => _classroom?.fields ?? [];
  int get currentIndex => _currentIndex;
  Student? get currentStudent => students.isEmpty
      ? null
      : students[_currentIndex.clamp(0, students.length - 1)];
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get error => _error;
  String? get lastSyncMessage => _lastSyncMessage;
  bool get isOnline => _isOnline;
  int get pendingCount => _pendingCount;

  /// Total possible points across all grade fields. Useful for percentage
  /// computations.
  double get totalPossible =>
      fields.fold<double>(0, (s, f) => s + f.max);

  /// Number of fully-graded students (have a value for every field).
  int get completedCount {
    if (fields.isEmpty) return 0;
    var cnt = 0;
    for (final s in students) {
      var ok = true;
      for (final f in fields) {
        if (!s.grades.containsKey(f.name)) {
          ok = false;
          break;
        }
      }
      if (ok) cnt++;
    }
    return cnt;
  }

  GradingProvider() {
    _pendingCount = StorageService.pendingCount;
    _isOnline = connectivityService.isOnline;
    connectivityService.onStatusChange.listen((online) {
      final wasOffline = !_isOnline;
      _isOnline = online;
      notifyListeners();
      // Auto-sync pending when back online
      if (online && wasOffline && _pendingCount > 0) {
        syncPendingGrades();
      }
    });
  }

  Future<void> loadClassroom({
    required int classId,
    required String className,
    required String subject,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    final cacheKey = 'class_${classId}_$subject';
    try {
      try {
        final data = await apiClient.getStudents(
          classId,
          subject,
          className: className,
        );
        _classroom = data;
        _currentIndex = 0;
        // Persist for offline access
        await StorageService.cacheClassroom(cacheKey, {
          'class_id': data.classId,
          'class_name': data.className,
          'subject': data.subject,
          'grade_structure': data.fields.map((f) => f.toJson()).toList(),
          'students': data.students.map((s) => s.toJson()).toList(),
        });
      } catch (apiErr) {
        // Fallback to cache
        final cached = StorageService.getCachedClassroom(cacheKey);
        if (cached != null) {
          _classroom = ClassroomData.fromJson(
            cached,
            className: className,
            subject: subject,
          );
          _currentIndex = 0;
          _error = 'تم التحميل من التخزين المحلي - وضع أوفلاين';
        } else {
          rethrow;
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateGrade(int studentIdx, String fieldName, double value) {
    if (_classroom == null) return;
    if (studentIdx < 0 || studentIdx >= students.length) return;
    final field = fields.firstWhere(
      (f) => f.name == fieldName,
      orElse: () => GradeField(name: fieldName, label: fieldName, max: 100),
    );
    final clamped = value.clamp(0, field.max).toDouble();
    students[studentIdx].grades[fieldName] = clamped;
    notifyListeners();
  }

  void setCurrentIndex(int idx) {
    if (idx < 0 || idx >= students.length) return;
    _currentIndex = idx;
    notifyListeners();
  }

  void nextStudent() {
    if (_currentIndex < students.length - 1) {
      _currentIndex++;
      notifyListeners();
    }
  }

  void previousStudent() {
    if (_currentIndex > 0) {
      _currentIndex--;
      notifyListeners();
    }
  }

  void clearCurrentGrades() {
    final s = currentStudent;
    if (s == null) return;
    s.grades.clear();
    notifyListeners();
  }

  /// Mark current student as absent: sets every field to 0.
  void markCurrentAbsent() {
    final s = currentStudent;
    if (s == null) return;
    for (final f in fields) {
      s.grades[f.name] = 0;
    }
    notifyListeners();
  }

  /// Save current student grades. Tries online sync first, queues offline
  /// on failure. Returns `true` if synced to the server, `false` if queued
  /// for later.
  Future<bool> saveCurrentStudent() async {
    final s = currentStudent;
    final c = _classroom;
    if (s == null || c == null) return false;

    final payload = PendingSync(
      studentId: s.id,
      studentName: s.name,
      grades: Map<String, double>.from(s.grades),
      timestamp: DateTime.now().toIso8601String(),
      classId: c.classId,
      subject: c.subject,
    );

    if (_isOnline) {
      try {
        await apiClient.syncGrades(
          termId: 1,
          weekNumber: 1,
          subject: c.subject,
          classId: c.classId,
          grades: [
            {
              'student_id': s.id,
              'grades': s.grades,
              'timestamp': payload.timestamp,
            },
          ],
        );
        return true;
      } catch (_) {
        await StorageService.addPendingSync(payload);
        _pendingCount = StorageService.pendingCount;
        notifyListeners();
        return false;
      }
    } else {
      await StorageService.addPendingSync(payload);
      _pendingCount = StorageService.pendingCount;
      notifyListeners();
      return false;
    }
  }

  /// Bulk save: persist grades for ALL students currently in memory.
  /// Useful at the end of a grading session before exporting.
  Future<int> saveAllStudents() async {
    if (_classroom == null) return 0;
    var saved = 0;
    final originalIndex = _currentIndex;
    try {
      for (var i = 0; i < students.length; i++) {
        // Skip students with no grades at all
        if (students[i].grades.isEmpty) continue;
        _currentIndex = i;
        final ok = await saveCurrentStudent();
        if (ok) saved++;
      }
    } finally {
      _currentIndex = originalIndex;
      notifyListeners();
    }
    return saved;
  }

  /// Sync all pending grades when back online.
  /// Returns the number of grades successfully synced.
  Future<int> syncPendingGrades() async {
    if (_isSyncing) return 0;
    final pending = StorageService.getPendingSyncs();
    if (pending.isEmpty) return 0;

    _isSyncing = true;
    _lastSyncMessage = null;
    notifyListeners();
    int synced = 0;
    final failed = <PendingSync>[];
    try {
      // Group by subject -> classId for batch syncing
      final bySubject = <String, List<PendingSync>>{};
      for (final p in pending) {
        bySubject.putIfAbsent(p.subject, () => []).add(p);
      }
      for (final entry in bySubject.entries) {
        final byClass = <int, List<PendingSync>>{};
        for (final p in entry.value) {
          byClass.putIfAbsent(p.classId, () => []).add(p);
        }
        for (final cEntry in byClass.entries) {
          try {
            await apiClient.syncGrades(
              termId: 1,
              weekNumber: 1,
              subject: entry.key,
              classId: cEntry.key,
              grades: cEntry.value
                  .map(
                    (e) => {
                      'student_id': e.studentId,
                      'grades': e.grades,
                      'timestamp': e.timestamp,
                    },
                  )
                  .toList(),
            );
            synced += cEntry.value.length;
          } catch (_) {
            failed.addAll(cEntry.value);
          }
        }
      }
      // Persist only the failed ones; everything synced is removed.
      if (failed.isEmpty) {
        await StorageService.clearPendingSyncs();
      } else if (synced > 0) {
        await StorageService.replacePendingSyncs(failed);
      }
      _pendingCount = StorageService.pendingCount;
      _lastSyncMessage = synced > 0
          ? 'تمت مزامنة $synced درجة بنجاح'
          : 'لا توجد بيانات تمت مزامنتها';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
    return synced;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void reset() {
    _classroom = null;
    _currentIndex = 0;
    _error = null;
    _lastSyncMessage = null;
    notifyListeners();
  }
}
