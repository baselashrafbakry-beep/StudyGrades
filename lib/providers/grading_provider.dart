import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/subscription_model.dart';
import '../models/academic_period.dart';
import '../models/student_model.dart';
import '../models/pending_sync.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../services/connectivity_service.dart';
import '../utils/error_handler.dart';

enum SaveStudentResult {
  synced,
  queued,
  localOnly,
  noGrades,
  queueFull,
  subscriptionBlocked,
}

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
  Subscription _subscription = Subscription.legacyActive();
  StreamSubscription<bool>? _connectivitySubscription;

  AcademicPeriod _period = const AcademicPeriod(termId: 1, weekNumber: 1);

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
  Subscription get subscription => _subscription;
  AcademicPeriod get period => _period;
  int get termId => _period.termId;
  int get weekNumber => _period.weekNumber;

  void setAcademicPeriod({required int termId, required int weekNumber}) {
    final next = AcademicPeriod.validated(
      termId: termId,
      weekNumber: weekNumber,
    );
    if (next.termId == _period.termId &&
        next.weekNumber == _period.weekNumber) {
      return;
    }
    _period = next;
    _classroom = null;
    _currentIndex = 0;
    _error = null;
    notifyListeners();
  }

  void setActiveOwner(String? ownerKey, {Subscription? subscription}) {
    final previousOwner = StorageService.activeOwnerKey;
    final previousSubscription = _subscription;
    _subscription = subscription ?? Subscription.legacyActive();
    StorageService.setActiveOwner(ownerKey);
    _pendingCount = StorageService.pendingCount;
    if (previousOwner != StorageService.activeOwnerKey) {
      reset(notify: false);
      notifyListeners();
    } else if (_subscriptionKey(previousSubscription) !=
        _subscriptionKey(_subscription)) {
      _applyCommercialClassroomLimits();
      notifyListeners();
    }
    if (StorageService.activeOwnerKey.isNotEmpty &&
        _isOnline &&
        _pendingCount > 0 &&
        _subscription.isUsable) {
      unawaited(Future<void>.microtask(syncPendingGrades));
    }
  }

  String _subscriptionKey(Subscription s) =>
      '${s.plan}|${s.status}|${s.expiresAt?.toIso8601String()}|${s.lifetime}';

  /// مجموع النقاط الممكنة لجميع البنود
  double get totalPossible => fields.fold<double>(0, (s, f) => s + f.max);

  /// عدد الطلاب المكتملة درجاتهم (لهم قيمة في كل بند)
  int get completedCount {
    if (fields.isEmpty) return 0;
    var cnt = 0;
    for (final s in students) {
      if (isStudentComplete(s)) cnt++;
    }
    return cnt;
  }

  int completedFieldCount(Student student) {
    return student.completedFieldCount(fields);
  }

  bool isStudentComplete(Student student) {
    return student.isCompleteFor(fields);
  }

  GradingProvider() {
    _pendingCount = StorageService.pendingCount;
    _isOnline = connectivityService.isOnline;
    _connectivitySubscription = connectivityService.onStatusChange.listen((
      online,
    ) {
      final wasOffline = !_isOnline;
      _isOnline = online;
      notifyListeners();
      // مزامنة تلقائية عند عودة الاتصال
      if (online && wasOffline && _pendingCount > 0) {
        syncPendingGrades();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> loadClassroom({
    required int classId,
    required String className,
    required String subject,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    final cacheKey = 'class_${classId}_${subject}_${_period.storageKey}';
    try {
      try {
        final data = await apiClient.getStudents(
          classId,
          subject,
          className: className,
          termId: termId,
          weekNumber: weekNumber,
        );
        _classroom = data;
        _applyCommercialClassroomLimits();
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
          _applyCommercialClassroomLimits();
          _currentIndex = 0;
          _error ??= 'تم التحميل من التخزين المحلي (وضع أوفلاين)';
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
  void loadDemoClassroom({required String className, required String subject}) {
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
    _applyCommercialClassroomLimits();
    _currentIndex = 0;
    _error = null;
    notifyListeners();
  }

  void _applyCommercialClassroomLimits() {
    final c = _classroom;
    if (c == null) return;
    if (!_subscription.isUsable) {
      _error = _subscription.blockedMessage('الفصول والدرجات');
      return;
    }
    final maxStudents = _subscription.limits.maxStudentsPerClass;
    if (maxStudents > 0 && c.students.length > maxStudents) {
      _classroom = ClassroomData(
        classId: c.classId,
        className: c.className,
        subject: c.subject,
        fields: c.fields,
        students: c.students.take(maxStudents).toList(growable: false),
      );
      _error =
          'خطة ${_subscription.planLabel} تعرض أول $maxStudents طالب فقط في الفصل. '
          'قم بترقية الخطة لفتح الفصل بالكامل.';
    }
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

  void updateGrade(int studentIdx, String fieldName, double? value) {
    if (_classroom == null) return;
    final list = students;
    if (studentIdx < 0 || studentIdx >= list.length) return;
    if (list[studentIdx].isLocked) return;
    if (value == null) {
      list[studentIdx].grades.remove(fieldName);
      notifyListeners();
      return;
    }
    final field = fields.firstWhere(
      (f) => f.name == fieldName,
      orElse: () => GradeField(name: fieldName, label: fieldName, max: 100),
    );
    final clamped = GradeField.clampGrade(value, field);
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
    if (s == null || s.isLocked) return;
    s.grades.clear();
    notifyListeners();
  }

  /// تسجيل الطالب الحالي غائباً: تعيين كل البنود = 0
  void markCurrentAbsent() {
    final s = currentStudent;
    if (s == null || s.isLocked) return;
    for (final f in fields) {
      s.grades[f.name] = 0;
    }
    notifyListeners();
  }

  /// حفظ الطالب الحالي. يحاول المزامنة أونلاين أولاً،
  /// ثم يحفظ في قائمة الانتظار عند الفشل.
  Future<SaveStudentResult> saveCurrentStudent() async {
    final s = currentStudent;
    final c = _classroom;
    if (s == null || c == null) return SaveStudentResult.noGrades;
    if (!_subscription.isUsable) {
      _error = _subscription.blockedMessage('حفظ الدرجات');
      notifyListeners();
      return SaveStudentResult.subscriptionBlocked;
    }

    final validGrades = <String, double>{};
    for (final field in fields) {
      final value = s.grades[field.name];
      if (value != null && value.isFinite) {
        validGrades[field.name] = GradeField.clampGrade(value, field);
      }
    }

    if (validGrades.isEmpty) return SaveStudentResult.noGrades;

    final payload = PendingSync(
      termId: termId,
      weekNumber: weekNumber,
      studentId: s.id,
      studentName: s.name,
      grades: validGrades,
      timestamp: DateTime.now().toIso8601String(),
      classId: c.classId,
      subject: c.subject,
      ownerKey: StorageService.activeOwnerKey,
    );

    // وضع العرض التجريبي (class_id=0) لا يُزامن
    if (c.classId == 0) {
      return SaveStudentResult.localOnly;
    }

    final queuedResult = await _queuePending(payload);
    if (queuedResult != SaveStudentResult.queued) return queuedResult;

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
              'grades': validGrades,
              'timestamp': payload.timestamp,
            },
          ],
        );
        await StorageService.removePendingForTarget(payload);
        _pendingCount = StorageService.pendingCount;
        notifyListeners();
        return SaveStudentResult.synced;
      } catch (e, st) {
        ErrorHandler.logError(e, st, 'GradingProvider.saveCurrentStudent');
        return SaveStudentResult.queued;
      }
    } else {
      return SaveStudentResult.queued;
    }
  }

  Future<SaveStudentResult> _queuePending(PendingSync payload) async {
    try {
      await StorageService.addPendingSync(
        payload,
        maxItemsForOwner: _subscription.limits.maxPendingSync,
      );
      _pendingCount = StorageService.pendingCount;
      notifyListeners();
      return SaveStudentResult.queued;
    } on StateError catch (e, st) {
      ErrorHandler.logError(e, st, 'GradingProvider.queuePending');
      _error = e.message;
      _pendingCount = StorageService.pendingCount;
      notifyListeners();
      return SaveStudentResult.queueFull;
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
        final result = await saveCurrentStudent();
        if (result == SaveStudentResult.synced ||
            result == SaveStudentResult.queued ||
            result == SaveStudentResult.localOnly) {
          saved++;
        }
      }
    } finally {
      // استعادة الفهرس الأصلي دائماً
      _currentIndex = originalIndex.clamp(
        0,
        list.isNotEmpty ? list.length - 1 : 0,
      );
      notifyListeners();
    }
    return saved;
  }

  /// مزامنة جميع الدرجات المعلقة عند توفر الاتصال.
  /// يُرجع عدد الدرجات التي تمت مزامنتها.
  Future<int> syncPendingGrades() async {
    if (_isSyncing) return 0;
    if (!_subscription.isUsable) {
      _lastSyncMessage = _subscription.blockedMessage('مزامنة الدرجات');
      notifyListeners();
      return 0;
    }
    final syncOwner = StorageService.activeOwnerKey;
    if (syncOwner.isEmpty) return 0;
    final pending = StorageService.getPendingSyncs();
    if (pending.isEmpty) return 0;

    _isSyncing = true;
    _lastSyncMessage = null;
    notifyListeners();
    int synced = 0;
    final delivered = <PendingSync>[];
    try {
      // تجميع حسب نفس هدف المزامنة حتى لا تنتقل درجات أسبوع/ترم إلى آخر.
      final byTarget = <String, List<PendingSync>>{};
      for (final p in pending) {
        final key = '${p.termId}|${p.weekNumber}|${p.classId}|${p.subject}';
        byTarget.putIfAbsent(key, () => []).add(p);
      }
      for (final entry in byTarget.entries) {
        if (StorageService.activeOwnerKey != syncOwner) break;
        final group = entry.value;
        final first = group.first;
        if (first.classId == 0) continue;
        try {
          await apiClient.syncGrades(
            termId: first.termId,
            weekNumber: first.weekNumber,
            subject: first.subject,
            classId: first.classId,
            grades: group
                .map(
                  (e) => {
                    'student_id': e.studentId,
                    'grades': e.grades,
                    'timestamp': e.timestamp,
                  },
                )
                .toList(),
          );
          synced += group.length;
          delivered.addAll(group);
        } catch (e, st) {
          ErrorHandler.logError(e, st, 'GradingProvider.syncPending');
        }
      }

      await StorageService.removeDeliveredPending(delivered);
      if (StorageService.activeOwnerKey == syncOwner) {
        _pendingCount = StorageService.pendingCount;
        _lastSyncMessage = synced > 0
            ? 'تمت مزامنة $synced درجة بنجاح'
            : 'لا توجد بيانات تمت مزامنتها';
      }
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

  void reset({bool notify = true}) {
    _classroom = null;
    _currentIndex = 0;
    _error = null;
    _lastSyncMessage = null;
    if (notify) notifyListeners();
  }
}
