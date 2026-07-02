import 'package:flutter/foundation.dart';
import '../models/student_model.dart';
import '../models/pending_sync.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../services/connectivity_service.dart';
import '../utils/error_handler.dart';

/// مزود الدرجات - يدير بيانات الفصل، مؤشر الطالب الحالي،
/// تحديثات الدرجات، والمزامنة أونلاين/أوفلاين
class GradingProvider extends ChangeNotifier {
  ClassroomData? _classroom;
  int _currentIndex = 0;
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _error;
  String? _lastSyncMessage;
  bool _isOnline = true;
  int _pendingCount = 0;

  /// معرف الفصل الدراسي - قابل للتعيين ديناميكياً بدلاً من التشفير
  int termId = 1;

  /// رقم الأسبوع - قابل للتعيين ديناميكياً بدلاً من التشفير
  int weekNumber = 1;

  ClassroomData? get classroom => _classroom;
  List<Student> get students => _classroom?.students ?? [];
  List<GradeField> get fields => _classroom?.fields ?? [];
  int get currentIndex => _currentIndex;

  /// الطالب الحالي مع حماية من الفهرس خارج الحدود
  Student? get currentStudent {
    final list = students;
    if (list.isEmpty) return null;
    final safeIdx = _currentIndex.clamp(0, list.length - 1);
    return list[safeIdx];
  }

  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get error => _error;
  String? get lastSyncMessage => _lastSyncMessage;
  bool get isOnline => _isOnline;
  int get pendingCount => _pendingCount;

  /// مجموع النقاط الممكنة لجميع البنود
  double get totalPossible =>
      fields.fold<double>(0, (s, f) => s + f.max);

  /// عدد الطلاب المكتملة درجاتهم (لهم قيمة في كل بند)
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
      // مزامنة تلقائية عند عودة الاتصال
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
        // حفظ محلي للوصول في وضع أوفلاين
        await StorageService.cacheClassroom(cacheKey, {
          'class_id': data.classId,
          'class_name': data.className,
          'subject': data.subject,
          'grade_structure': data.fields.map((f) => f.toJson()).toList(),
          'students': data.students.map((s) => s.toJson()).toList(),
        });
      } catch (apiErr) {
        // الرجوع للكاش المحلي
        final cached = StorageService.getCachedClassroom(cacheKey);
        if (cached != null) {
          _classroom = ClassroomData.fromJson(
            cached,
            className: className,
            subject: subject,
          );
          _currentIndex = 0;
          _error = 'تم التحميل من التخزين المحلي (وضع أوفلاين)';
        } else {
          rethrow;
        }
      }
    } catch (e) {
      _error = ErrorHandler.humanize(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// تحميل بيانات تجريبية بدون API (للاختبار والعرض)
  void loadDemoClassroom({
    required String className,
    required String subject,
  }) {
    const fields = [
      {'name': 'oral', 'label': 'شفهي', 'max': 15.0},
      {'name': 'written', 'label': 'تحريري', 'max': 25.0},
      {'name': 'activity', 'label': 'نشاط', 'max': 10.0},
    ];

    final students = List.generate(10, (i) {
      final num = (i + 1).toString().padLeft(3, '0');
      return {
        'id': i + 1,
        'student_number': num,
        'name': _demoNames[i % _demoNames.length],
        'existing_grades': {},
      };
    });

    _classroom = ClassroomData.fromJson(
      {
        'class_id': 0,
        'class_name': className,
        'subject': subject,
        'grade_structure': fields,
        'students': students,
      },
      className: className,
      subject: subject,
    );
    _currentIndex = 0;
    _error = null;
    notifyListeners();
  }

  static const _demoNames = [
    'أحمد محمد علي',
    'فاطمة أحمد حسن',
    'محمود عبد الله',
    'مريم يوسف إبراهيم',
    'علي حسن مصطفى',
    'نورا إبراهيم سالم',
    'كريم سمير عمر',
    'رنا طارق محمد',
    'عمر خالد عبد الرحمن',
    'هدى سعيد عثمان',
  ];

  void updateGrade(int studentIdx, String fieldName, double value) {
    if (_classroom == null) return;
    final list = students;
    if (studentIdx < 0 || studentIdx >= list.length) return;
    final field = fields.firstWhere(
      (f) => f.name == fieldName,
      orElse: () => GradeField(name: fieldName, label: fieldName, max: 100),
    );
    final clamped = value.clamp(0, field.max).toDouble();
    list[studentIdx].grades[fieldName] = clamped;
    notifyListeners();
  }

  void setCurrentIndex(int idx) {
    final list = students;
    if (list.isEmpty) return;
    _currentIndex = idx.clamp(0, list.length - 1);
    notifyListeners();
  }

  void nextStudent() {
    final list = students;
    if (_currentIndex < list.length - 1) {
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

  /// تسجيل الطالب الحالي غائباً: تعيين كل البنود = 0
  void markCurrentAbsent() {
    final s = currentStudent;
    if (s == null) return;
    for (final f in fields) {
      s.grades[f.name] = 0;
    }
    notifyListeners();
  }

  /// حفظ الطالب الحالي. يحاول المزامنة أونلاين أولاً،
  /// ثم يحفظ في قائمة الانتظار عند الفشل.
  /// يُرجع true عند المزامنة الناجحة، false عند الحفظ المحلي.
  Future<bool> saveCurrentStudent() async {
    final s = currentStudent;
    final c = _classroom;
    if (s == null || c == null) return false;

    // لا حاجة لحفظ طالب فارغ الدرجات
    if (s.grades.isEmpty) return false;

    final payload = PendingSync(
      studentId: s.id,
      studentName: s.name,
      grades: Map<String, double>.from(s.grades),
      timestamp: DateTime.now().toIso8601String(),
      classId: c.classId,
      subject: c.subject,
    );

    // وضع العرض التجريبي (class_id=0) لا يُزامن ولا يُضاف للـ pendingQueue
    // إصلاح: كان يُضيف للـ pending رغم أنه لن يُزامن أبداً → يراكم بيانات وهمية
    if (c.classId == 0) {
      return false; // نجاح محلي فقط — بدون إضافة للـ queue
    }

    if (_isOnline) {
      try {
        await apiClient.syncGrades(
          termId: termId,
          weekNumber: weekNumber,
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
      } catch (e, st) {
        ErrorHandler.logError(e, st, 'GradingProvider.saveCurrentStudent');
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

  /// حفظ جماعي: يحفظ درجات جميع الطلاب.
  /// إصلاح ثغرة: حفظ الفهرس الأصلي قبل الدوران عليه
  Future<int> saveAllStudents() async {
    if (_classroom == null) return 0;
    var saved = 0;
    final originalIndex = _currentIndex;
    final list = students;
    try {
      for (var i = 0; i < list.length; i++) {
        if (list[i].grades.isEmpty) continue;
        _currentIndex = i;
        final ok = await saveCurrentStudent();
        if (ok) saved++;
      }
    } finally {
      // استعادة الفهرس الأصلي دائماً
      _currentIndex = originalIndex.clamp(0, list.isNotEmpty ? list.length - 1 : 0);
      notifyListeners();
    }
    return saved;
  }

  /// مزامنة جميع الدرجات المعلقة عند توفر الاتصال.
  /// يُرجع عدد الدرجات التي تمت مزامنتها.
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
      // تجميع حسب المادة ثم الفصل
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
          // تخطي فصل العرض التجريبي
          if (cEntry.key == 0) continue;
          try {
            await apiClient.syncGrades(
              termId: termId,
              weekNumber: weekNumber,
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
          } catch (e, st) {
            ErrorHandler.logError(e, st, 'GradingProvider.syncPending');
            failed.addAll(cEntry.value);
          }
        }
      }

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
