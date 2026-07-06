import 'package:flutter/foundation.dart';
import '../models/student_model.dart';
import '../models/pending_sync.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../services/connectivity_service.dart';
import '../services/subscription_service.dart';
import '../utils/error_handler.dart';

/// مزود الدرجات - يدير بيانات الفصل، مؤشر الطالب الحالي،
/// تحديثات الدرجات، والمزامنة أونلاين/أوفلاين
class GradingProvider extends ChangeNotifier {
  ClassroomData? _classroom;
  int _currentIndex = 0;
  bool _gradingFinished =
      false; // علم انتهاء الدرجات — يجعل currentStudent يرجع null لتفعيل شاشة الاحتفال
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _error;
  String? _lastSyncMessage;
  bool _isOnline = true;
  int _pendingCount = 0;

  /// عدد الطلاب الذين تم استبعادهم من القائمة بسبب تجاوز حد الخطة
  /// الحالية (maxStudentsPerClass) — 0 يعني عدم وجود أي قصّ.
  int _trimmedStudentsCount = 0;
  int get trimmedStudentsCount => _trimmedStudentsCount;

  /// يُرفع إلى true عند رفض فتح فصل جديد لتجاوز حد عدد الفصول
  /// (maxClassesPerTeacher) الخاص بالباقة الحالية.
  bool _classLimitExceeded = false;
  bool get classLimitExceeded => _classLimitExceeded;

  /// معرف الفصل الدراسي - قابل للتعيين ديناميكياً بدلاً من التشفير
  int termId = 1;

  /// رقم الأسبوع - قابل للتعيين ديناميكياً بدلاً من التشفير
  int weekNumber = 1;

  // ────────────────────────────────────────────────────────────────
  // نقاط حَقن للاختبار فقط (Testability Seams) — لا تُستخدَم في كود
  // الإنتاج الفعلي إطلاقاً؛ الهدف تمكين اختبار وحدات (unit tests)
  // حتمية لسيناريوهات الشبكة/الاتصال دون:
  //   1) إجراء اتصال شبكة حقيقي بخادم الإنتاج (apiClient يستهدف
  //      رابط production ثابت افتراضياً).
  //   2) الاعتماد على حزمة connectivity_plus التي تستخدم MethodChannel
  //      أصلي غير مسجَّل في بيئة `flutter test` (Dart VM) فتُطلق
  //      MissingPluginException عند استدعاء init() الحقيقية.
  // كل النقاط أدناه اختيارية (nullable) وتبقى null في كود الإنتاج،
  // فيُستخدَم السلوك الحقيقي كما هو تماماً دون أي تأثير.
  // ────────────────────────────────────────────────────────────────

  /// دالة بديلة لـ `apiClient.syncGrades` — تُستخدَم في الاختبارات
  /// للتحكم الحتمي في نجاح/فشل "المزامنة" دون اتصال شبكة فعلي.
  @visibleForTesting
  Future<Map<String, dynamic>> Function({
    required int termId,
    required int weekNumber,
    required String subject,
    required List<Map<String, dynamic>> grades,
    int? classId,
  })? debugSyncOverride;

  /// يفرض حالة الاتصال يدوياً في الاختبارات (بدلاً من انتظار
  /// connectivityService الحقيقية التي تحتاج MethodChannel أصلي).
  @visibleForTesting
  void debugSetOnline(bool online) {
    _isOnline = online;
    notifyListeners();
  }

  /// يحقن فصلاً دراسياً جاهزاً مباشرةً في الاختبارات (بدلاً من
  /// المرور عبر loadClassroom() التي تتطلب اتصال شبكة حقيقي).
  @visibleForTesting
  void debugSetClassroom(ClassroomData data) {
    _classroom = data;
    _currentIndex = 0;
    _gradingFinished = false;
    notifyListeners();
  }

  ClassroomData? get classroom => _classroom;
  List<Student> get students => _classroom?.students ?? [];
  List<GradeField> get fields => _classroom?.fields ?? [];
  int get currentIndex => _currentIndex;

  bool get isGradingFinished => _gradingFinished;

  /// الطالب الحالي — يرجع null عند انتهاء جميع الطلاب (يتيح عرض شاشة الاحتفال)
  Student? get currentStudent {
    // إذا رُفع علم الانتهاء → شاشة الاحتفال تظهر في grading_screen.dart
    if (_gradingFinished) return null;
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
  double get totalPossible => fields.fold<double>(0, (s, f) => s + f.max);

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

    // 🔴 إصلاح ثغرة "فقدان مزامنة بدء التشغيل الباردة" (Cold-Start Sync
    // Gap — اكتُشفت أثناء تدقيق Pillar 3 لوضع عدم الاتصال):
    //
    // كانت المزامنة التلقائية تعتمد حصرياً على الاستماع لـ
    // `connectivityService.onStatusChange`، والذي لا يُطلِق حدثاً إلا
    // عند حدوث *تغيّر فعلي* في حالة الاتصال (أوفلاين → أونلاين) أثناء
    // تشغيل التطبيق. لكن هذا الـ Stream هو `broadcast` عادي بلا "replay"
    // للأحداث الفائتة — والحدث الأول (`init()` في connectivityService)
    // يُطلَق في `main()` **قبل** إنشاء `GradingProvider` (الذي يُنشأ
    // بشكل كسول `lazy: true` عند أول استخدام فعلي للمزود)، فيفوت هذا
    // الحدث الأول تماماً.
    //
    // السيناريو الحقيقي المتأثر (شائع جداً): يُغلق المستخدم التطبيق
    // بينما يوجد لديه درجات معلّقة في قائمة الانتظار (Hive) بسبب انقطاع
    // اتصال سابق، ثم يعيد فتح التطبيق **وهو متصل بالفعل** بالإنترنت
    // (واي فاي/بيانات جوال) منذ البداية. في هذه الحالة لا يحدث أي
    // "تحوّل" (transition) من أوفلاين لأونلاين على الإطلاق أثناء عمر
    // التطبيق — فتبقى الدرجات المعلّقة عالقة بصمت في Hive إلى أن يكتشف
    // المستخدم يدوياً وجود بيانات معلّقة ويضغط زر "مزامنة" يدوياً.
    //
    // ✅ الإصلاح: عند إنشاء GradingProvider، إذا كان الجهاز متصلاً
    // بالفعل ويوجد عناصر معلّقة من جلسة سابقة → نُطلق محاولة مزامنة
    // فورية دون انتظار أي "تحوّل" في حالة الاتصال. العملية غير حاجبة
    // (fire-and-forget)، ومحمية داخلياً بعلم `_isSyncing` في
    // `syncPendingGrades()` نفسها لمنع أي تكرار أو تعارض مع أي مزامنة
    // أخرى قد تبدأ لاحقاً (مثل حدث onStatusChange الحقيقي إن حدث).
    //
    // نُؤجّل الاستدعاء عبر `Future.microtask` (وليس مباشرة داخل الـ
    // constructor) لسببين:
    //   1) اختباري: يسمح لكود الاختبار بحقن `debugSyncOverride` مباشرةً
    //      بعد إنشاء الكائن (`GradingProvider()`) قبل أن تبدأ محاولة
    //      المزامنة الفعلية بمايكروثانية واحدة فقط — بدون هذا التأجيل
    //      كانت ستُستدعى `apiClient.syncGrades` الحقيقية فوراً وبشكل
    //      متزامن أثناء تنفيذ الـ constructor نفسه، قبل أي فرصة للاختبار
    //      لحقن البديل الآمن.
    //   2) عملي: يتجنّب تنفيذ منطق I/O أثناء بناء الكائن مباشرة، وهو
    //      نمط أكثر أماناً بشكل عام في constructors غير متزامنة.
    if (_isOnline && _pendingCount > 0) {
      Future.microtask(() {
        // ignore: unawaited_futures
        syncPendingGrades();
      });
    }
  }

  /// يُعيد مزامنة `_pendingCount` مع القيمة الفعلية في `StorageService`
  /// (يُستخدم بعد عمليات خارجية تُعدّل صندوق pending_grades_box مباشرة،
  /// مثل مسح كل البيانات المحلية من شاشة الإعدادات).
  void refreshPendingCount() {
    _pendingCount = StorageService.pendingCount;
    notifyListeners();
  }

  Future<void> loadClassroom({
    required int classId,
    required String className,
    required String subject,
  }) async {
    _isLoading = true;
    _error = null;
    _classLimitExceeded = false;
    _trimmedStudentsCount = 0;
    notifyListeners();

    // فرض حد عدد الفصول (maxClassesPerTeacher) حسب باقة الاشتراك الحالية،
    // قبل أي استدعاء للسيرفر — يُستثنى فصل العرض التجريبي (classId == 0).
    final canOpen = await SubscriptionService.canOpenClass(classId);
    if (!canOpen) {
      _classLimitExceeded = true;
      _isLoading = false;
      notifyListeners();
      return;
    }

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

      // فرض حد عدد الطلاب بالفصل (maxStudentsPerClass) حسب الباقة الحالية:
      // نقصّ القائمة فعلياً على مستوى البيانات (وليس مجرد تحذير شكلي)
      // حتى لا يتمكن المستخدم من رصد/تصدير درجات طلاب يتجاوزون حد باقته.
      final maxStudents = await SubscriptionService.getMaxStudentsPerClass();
      final c = _classroom;
      if (c != null && maxStudents != -1 && c.students.length > maxStudents) {
        _trimmedStudentsCount = c.students.length - maxStudents;
        _classroom = ClassroomData(
          classId: c.classId,
          className: c.className,
          subject: c.subject,
          fields: c.fields,
          students: c.students.sublist(0, maxStudents),
        );
      }

      // سجّل هذا الفصل كمفتوح فعلياً بعد نجاح التحميل (من السيرفر أو الكاش)
      await SubscriptionService.markClassOpened(classId);
    } catch (e) {
      _error = ErrorHandler.humanize(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

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

  /// انتقال للطالب التالي — للاستخدام العادي بين الطلاب
  void nextStudent() {
    final list = students;
    if (_currentIndex < list.length - 1) {
      _currentIndex++;
      notifyListeners();
    }
    // لاحظ: عند آخر طالب يستخدم finishGrading() بدلاً من هذه
  }

  /// إنهاء جلسة التصحيح — يرفع علم الانتهاء لتفعيل شاشة الاحتفال
  void finishGrading() {
    _gradingFinished = true;
    notifyListeners();
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
  ///
  /// إصلاح ثغرة أمنية حرجة (فقدان بيانات — Pillar 1 Edge Case: "المستخدم
  /// يغلق التطبيق فجأة أثناء الحفظ"):
  /// كان الكود القديم يكتب إلى Hive (قائمة الانتظار المحلية) فقط **بعد**
  /// فشل استدعاء الشبكة (داخل `catch`) أو في الفرع الأوفلاين الصريح.
  /// أثناء انتظار `await apiClient.syncGrades(...)` (وهو ما قد يستغرق
  /// ثوانٍ على شبكة بطيئة)، كانت الدرجات موجودة في الذاكرة (RAM) فقط —
  /// فإذا أنهى نظام التشغيل عملية التطبيق فجأة (نفاد ذاكرة، إغلاق قسري
  /// من المستخدم، انقطاع الاتصال بشكل يُعلّق طلب الشبكة طويلاً...) في
  /// هذه النافذة الزمنية، تُفقَد درجات الطالب نهائياً دون أي أثر محلي.
  ///
  /// الإصلاح: نطبّق نمط "Write-Ahead Log" — نكتب الحمولة إلى صندوق
  /// الانتظار في Hive **أولاً وقبل أي استدعاء شبكة على الإطلاق**، ثم
  /// نحاول المزامنة، ثم نحذفها من قائمة الانتظار فقط عند نجاح المزامنة
  /// الفعلي. هذا يضمن أن البيانات محفوظة على القرص بشكل دائم بغضّ النظر
  /// عن اللحظة التي يُغلَق فيها التطبيق أو تنقطع الشبكة.
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

    // ── خطوة الأمان الأولى (Write-Ahead): اكتب على القرص فوراً، قبل أي
    // انتظار شبكة، بحيث تكون الدرجات مؤمَّنة محلياً حتى لو أُغلِق
    // التطبيق في اللحظة التالية مباشرةً. ──
    await StorageService.addPendingSync(payload);
    _pendingCount = StorageService.pendingCount;
    notifyListeners();

    if (!_isOnline) {
      // أوفلاين: البيانات محفوظة بالفعل في قائمة الانتظار أعلاه، تنتظر
      // المزامنة التلقائية عند عودة الاتصال (راجع مُنشئ الكلاس).
      return false;
    }

    try {
      final syncFn = debugSyncOverride ?? apiClient.syncGrades;
      await syncFn(
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
      // نجحت المزامنة: احذف هذا العنصر تحديداً من قائمة الانتظار (وليس
      // القائمة كلها) لتفادي حذف عناصر أخرى معلّقة من طلاب/مواد مختلفين
      // قد تكون أُضيفت بالتوازي أثناء انتظار هذا الطلب.
      await StorageService.removePendingSync(
        studentId: s.id,
        subject: c.subject,
      );
      _pendingCount = StorageService.pendingCount;
      notifyListeners();
      return true;
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'GradingProvider.saveCurrentStudent');
      // فشلت المزامنة: البيانات محفوظة بالفعل في قائمة الانتظار من
      // خطوة الـ Write-Ahead أعلاه — لا حاجة لأي إجراء إضافي، ستتم
      // المزامنة تلقائياً لاحقاً عبر syncPendingGrades().
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
      _currentIndex =
          originalIndex.clamp(0, list.isNotEmpty ? list.length - 1 : 0);
      notifyListeners();
    }
    return saved;
  }

  /// مزامنة جميع الدرجات المعلقة عند توفر الاتصال.
  /// يُرجع عدد الدرجات التي تمت مزامنتها.
  ///
  /// 🔴 إصلاح ثغرة حرجة إضافية (اكتُشفت أثناء تدقيق Pillar 1 — Race
  /// Condition / فقدان بيانات صامت):
  /// كانت النسخة القديمة تأخذ لقطة (snapshot) واحدة من قائمة الانتظار
  /// في بداية الدالة `pending = StorageService.getPendingSyncs()`، ثم
  /// بعد إتمام حلقة المزامنة (التي قد تستغرق عدة ثوانٍ لعدة طلبات
  /// شبكة)، كانت تُنفّذ إما:
  ///   • `clearPendingSyncs()` → يمسح **الصندوق بأكمله** في Hive، أو
  ///   • `replacePendingSyncs(failed)` → **يستبدل الصندوق بأكمله**
  ///     بقائمة العناصر الفاشلة فقط.
  /// المشكلة: إذا أضاف المستخدم درجة طالب جديدة أثناء تشغيل هذه
  /// الدالة (مثلاً عبر `saveCurrentStudent()` لطالب آخر بينما هو
  /// يواصل التصحيح، أو مزامنة تلقائية عند عودة الاتصال بينما المستخدم
  /// نشط) — فإن هذا العنصر الجديد **غير موجود في اللقطة الأصلية**،
  /// لكنه **مكتوب بالفعل على القرص** (Write-Ahead) في تلك اللحظة.
  /// عند وصول الدالة لنهايتها وتنفيذ `clearPendingSyncs()` أو
  /// `replacePendingSyncs()` المستندين على اللقطة القديمة، كان هذا
  /// العنصر الجديد **يُحذَف بصمت نهائياً** رغم أنه لم يُحاوَل مزامنته
  /// إطلاقاً — فقدان بيانات كامل دون أي رسالة خطأ.
  ///
  /// ✅ الإصلاح: نفس نمط "الحذف الانتقائي الآمن" المُستخدَم في
  /// `saveCurrentStudent()` — بعد نجاح مزامنة كل دفعة (subject+classId)
  /// نحذف فقط عناصرها بالتحديد عبر `removePendingSync()`، بدلاً من أي
  /// عملية مسح/استبدال شاملة تعتمد على لقطة قديمة. أي عنصر جديد يُضاف
  /// أثناء تشغيل الدالة يبقى في الصندوق بأمان تام ولا يُلمَس أبداً ما
  /// لم تتم مزامنته صراحةً هو نفسه.
  Future<int> syncPendingGrades() async {
    if (_isSyncing) return 0;
    final pending = StorageService.getPendingSyncs();
    if (pending.isEmpty) return 0;

    _isSyncing = true;
    _lastSyncMessage = null;
    notifyListeners();
    int synced = 0;
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
            final syncFn = debugSyncOverride ?? apiClient.syncGrades;
            await syncFn(
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
            // نجحت مزامنة هذه الدفعة تحديداً: احذف عناصرها فقط، عنصراً
            // عنصراً، بدل أي مسح/استبدال شامل للصندوق يعتمد على لقطة
            // قديمة (راجع شرح إصلاح الـ Race Condition أعلاه).
            for (final item in cEntry.value) {
              await StorageService.removePendingSync(
                studentId: item.studentId,
                subject: item.subject,
              );
            }
            synced += cEntry.value.length;
          } catch (e, st) {
            ErrorHandler.logError(e, st, 'GradingProvider.syncPending');
            // فشلت هذه الدفعة: نتركها كما هي في الصندوق دون أي حذف —
            // ستُعاد محاولة مزامنتها تلقائياً في الاستدعاء التالي.
          }
        }
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
    _gradingFinished = false; // إعادة تعيين علم الانتهاء عند بدء جلسة جديدة
    _error = null;
    _lastSyncMessage = null;
    _trimmedStudentsCount = 0;
    _classLimitExceeded = false;
    notifyListeners();
  }
}
