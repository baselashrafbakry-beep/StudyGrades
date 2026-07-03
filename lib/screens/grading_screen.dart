import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../providers/grading_provider.dart';
import '../providers/auth_provider.dart';
import '../services/admin_service.dart';
import '../services/api_client.dart';
import '../services/voice_service.dart';
import '../services/nlp_parser.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../widgets/recording_button.dart';
import '../widgets/grade_field_card.dart';
import 'students_list_screen.dart';
import 'dashboard_screen.dart';

/// Smart grading screen with continuous voice mode.
///
/// Workflow (Smart Mode - default):
///   1. Tap mic once -> continuous listening starts.
///   2. Teacher speaks first grade ("خمسة عشر") -> recognized -> assigned to
///      current field -> auto-advance to next field.
///   3. Repeats until all fields have grades.
///   4. Confirmation dialog appears showing all grades for the current student.
///   5. Teacher confirms -> auto-save -> auto-advance to next student -> resume listening.
///   6. After last student -> show "all done" celebration.
///
/// Voice commands during listening:
///   - "صفر" / "خمسة" / numbers -> assign to current field
///   - "كاملة" -> assign max value to current field
///   - "غائب" -> mark all fields = 0 and advance
///   - "السابق" -> previous student
///   - "التالي" -> save & next
///   - "امسح" -> clear current student grades
///   - "إيقاف" / "حفظ" -> stop the auto-loop
class GradingScreen extends StatefulWidget {
  final int classId;
  final String className;
  final String subject;

  const GradingScreen({
    super.key,
    required this.classId,
    required this.className,
    required this.subject,
  });

  @override
  State<GradingScreen> createState() => _GradingScreenState();
}

class _GradingScreenState extends State<GradingScreen> {
  // ===== Voice state =====
  bool _isProcessing = false;
  String _transcript = '';
  bool _useServerTranscription = false;

  /// سقف إداري: عندما يُعطّل المطور "الإدخال الصوتي السحابي" من إعدادات
  /// النظام، لا يُسمح باستخدام مسار Whisper AI (السيرفر) إطلاقاً هنا،
  /// حتى لو كان المستخدم قد فعّله سابقاً في هذه الجلسة.
  bool _serverSpeechAllowedBySystem = true;

  /// سقف إداري: عندما يُعطّل المطور "الوضع الأوفلاين" من إعدادات النظام،
  /// يُمنع المستخدم من الاستمرار في الرصد بدون اتصال إنترنت فعلي.
  bool _offlineModeAllowedBySystem = true;

  // ===== Smart mode (auto-advance + continuous listen) =====
  bool _smartMode = true;
  int _currentFieldIndex = 0;
  bool _autoLoopActive = false;
  bool _isStoppingLoop = false;
  bool _showingConfirm = false;

  // Highlight tracking for visual feedback
  String? _justFilledField;

  @override
  void initState() {
    super.initState();
    _initVoice();
    _loadSystemFeatureFlags();
    // تتبع استخدام: بدء جلسة رصد جديدة (لأغراض إحصاءات المطور فقط،
    // ولا يعمل إطلاقاً إذا كانت التحليلات معطّلة من إعدادات النظام)
    AdminService.trackEvent('grading_session_started');
  }

  Future<void> _loadSystemFeatureFlags() async {
    final serverSpeechAllowed = await AdminService.isServerSpeechEnabled();
    final offlineAllowed = await AdminService.isOfflineModeEnabled();
    if (!mounted) return;
    setState(() {
      _serverSpeechAllowedBySystem = serverSpeechAllowed;
      _offlineModeAllowedBySystem = offlineAllowed;
      // إذا عطّل المطور الميزة على مستوى النظام، أوقف استخدامها فوراً
      // حتى لو كانت مفعّلة محلياً في نفس الجلسة.
      if (!serverSpeechAllowed) _useServerTranscription = false;
    });
  }

  @override
  void dispose() {
    _autoLoopActive = false;
    voiceService.cancelListening();
    super.dispose();
  }

  Future<void> _initVoice() async {
    final granted = await voiceService.requestPermissions();
    if (!granted) {
      _toast('برجاء السماح باستخدام الميكروفون', error: true);
      return;
    }
    await voiceService.initSpeech();
    if (mounted) {
      // Force rebuild so first-empty field gets highlighted
      setState(() => _resetFieldFocus(toFirstEmpty: true));
    }
  }

  void _toast(String msg, {bool error = false, bool success = false}) {
    Fluttertoast.showToast(
      msg: msg,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: error
          ? AppColors.error
          : success
          ? AppColors.success
          : AppColors.primary,
      textColor: Colors.white,
      toastLength: Toast.LENGTH_SHORT,
    );
  }

  // =================== Smart Auto Mode ===================
  void _resetFieldFocus({bool toFirstEmpty = true}) {
    final grading = context.read<GradingProvider>();
    if (grading.fields.isEmpty) {
      _currentFieldIndex = 0;
      return;
    }
    if (toFirstEmpty) {
      final cur = grading.currentStudent;
      if (cur != null) {
        for (var i = 0; i < grading.fields.length; i++) {
          final f = grading.fields[i];
          if (!cur.grades.containsKey(f.name)) {
            _currentFieldIndex = i;
            return;
          }
        }
        // All fields filled
        _currentFieldIndex = grading.fields.length;
        return;
      }
    }
    _currentFieldIndex = 0;
  }

  Future<void> _stopAutoLoop({bool silent = false}) async {
    _isStoppingLoop = true;
    _autoLoopActive = false;
    await voiceService.cancelListening();
    if (voiceService.isRecording) {
      await voiceService.stopRecording();
    }
    if (mounted) {
      setState(() => _isProcessing = false);
    }
    _isStoppingLoop = false;
    if (!silent && mounted) _toast('تم إيقاف الوضع التلقائي');
  }

  Future<void> _startAutoLoop() async {
    HapticFeedback.mediumImpact();
    final grading = context.read<GradingProvider>();
    if (grading.fields.isEmpty || grading.currentStudent == null) {
      _toast('لا توجد بنود للتقييم', error: true);
      return;
    }

    if (!voiceService.speechAvailable) {
      final ok = await voiceService.initSpeech();
      if (!ok) {
        _toast('التعرف الصوتي غير متاح، فعّل خدمات Google', error: true);
        return;
      }
    }

    _resetFieldFocus(toFirstEmpty: true);
    _autoLoopActive = true;
    if (mounted) {
      setState(() {
        _transcript = '';
        _justFilledField = null;
      });
    }

    while (_autoLoopActive && mounted) {
      if (!_autoLoopActive || _isStoppingLoop || _showingConfirm) break;

      try {
        final text = await voiceService.listenOnce(
          listenFor: const Duration(seconds: 8),
          pauseFor: const Duration(seconds: 2),
          onPartial: (p) {
            if (mounted) setState(() => _transcript = p);
          },
        );

        if (!_autoLoopActive || !mounted) break;

        if (mounted) {
          setState(() {
            _transcript = text;
            _isProcessing = true;
          });
        }

        if (text.trim().isEmpty) {
          if (mounted) setState(() => _isProcessing = false);
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }

        final action = await _handleSmartUtterance(text);
        if (!_autoLoopActive || !mounted) break;
        if (mounted) setState(() => _isProcessing = false);

        if (action == _SmartAction.stop) {
          _autoLoopActive = false;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 250));
      } catch (e) {
        if (!mounted) break;
        if (mounted) setState(() => _isProcessing = false);
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    if (mounted) {
      setState(() => _autoLoopActive = false);
    }
  }

  Future<_SmartAction> _handleSmartUtterance(String text) async {
    final grading = context.read<GradingProvider>();
    final result = NLPParser.parse(text);

    if (result.hasStop) {
      _toast('تم إيقاف الوضع التلقائي');
      return _SmartAction.stop;
    }
    if (result.hasClear) {
      grading.clearCurrentGrades();
      _resetFieldFocus(toFirstEmpty: true);
      _toast('تم مسح الدرجات');
      HapticFeedback.lightImpact();
      return _SmartAction.cleared;
    }
    if (result.hasAbsent) {
      for (final f in grading.fields) {
        grading.updateGrade(grading.currentIndex, f.name, 0);
      }
      _toast('تم تسجيل الطالب كغائب');
      await _showConfirmAndAdvance(autoAdvance: true);
      return _SmartAction.absent;
    }
    if (result.hasPrevious) {
      grading.previousStudent();
      _resetFieldFocus(toFirstEmpty: true);
      if (mounted) setState(() {});
      _toast('الطالب السابق');
      return _SmartAction.previous;
    }
    if (result.hasNext) {
      await _showConfirmAndAdvance(autoAdvance: true);
      return _SmartAction.next;
    }
    if (result.hasSave) {
      await _save(silent: false);
      return _SmartAction.stop;
    }

    // Voice command "كاملة" / "full" -> assign max to current field
    if (result.hasFull) {
      final fields = grading.fields;
      if (_currentFieldIndex < fields.length) {
        final f = fields[_currentFieldIndex];
        grading.updateGrade(grading.currentIndex, f.name, f.max);
        if (mounted) setState(() => _justFilledField = f.name);
        HapticFeedback.lightImpact();
        _currentFieldIndex++;
        if (_currentFieldIndex >= fields.length) {
          return await _onAllFieldsFilled();
        }
        return _SmartAction.assigned;
      }
    }

    if (result.numbers.isEmpty) {
      _toast('لم يتم التعرف على رقم، حاول مرة أخرى');
      return _SmartAction.none;
    }

    return await _assignNumbersSequentially(result.numbers, grading);
  }

  Future<_SmartAction> _assignNumbersSequentially(
    List<double> numbers,
    GradingProvider grading,
  ) async {
    final fields = grading.fields;
    final cur = grading.currentStudent;
    if (cur == null) return _SmartAction.none;

    int n = 0;
    int i = _currentFieldIndex;
    String? lastField;

    while (n < numbers.length && i < fields.length) {
      final f = fields[i];
      final clamped = numbers[n].clamp(0, f.max).toDouble();
      grading.updateGrade(grading.currentIndex, f.name, clamped);
      lastField = f.name;
      i++;
      n++;
    }

    _currentFieldIndex = i;
    if (lastField != null && mounted) {
      setState(() => _justFilledField = lastField);
    }

    HapticFeedback.lightImpact();
    if (numbers.length == 1) {
      _toast('تم رصد الدرجة', success: true);
    } else {
      _toast('تم رصد ${numbers.length} درجات', success: true);
    }

    if (_currentFieldIndex >= fields.length) {
      return await _onAllFieldsFilled();
    }

    return _SmartAction.assigned;
  }

  Future<_SmartAction> _onAllFieldsFilled() async {
    // لا نوقف _autoLoopActive هنا — نتركه true حتى يقرر الـ dialog
    // نوقف الاستماع مؤقتاً فقط
    await voiceService.cancelListening();
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return _SmartAction.stop;

    _showingConfirm = true;
    final confirmed = await _showConfirmDialog();
    _showingConfirm = false;

    if (confirmed == true) {
      await _doAdvanceToNext();
      if (!mounted) return _SmartAction.stop;
      final grading = context.read<GradingProvider>();
      if (grading.currentStudent != null) {
        // لا زال هناك طلاب — أعد تفعيل الحلقة
        _autoLoopActive = true;
        _resetFieldFocus(toFirstEmpty: true);
      } else {
        // انتهت القائمة
        _autoLoopActive = false;
      }
      return _SmartAction.next;
    } else if (confirmed == false) {
      // وضع التعديل — أعد الاستماع
      _resetFieldFocus(toFirstEmpty: true);
      _autoLoopActive = true;
      return _SmartAction.none;
    } else {
      // إغلاق بالضغط خارج الـ dialog → إيقاف الحلقة
      _autoLoopActive = false;
      return _SmartAction.stop;
    }
  }

  Future<void> _showConfirmAndAdvance({required bool autoAdvance}) async {
    if (!autoAdvance) return;
    await _doAdvanceToNext();
  }

  Future<void> _doAdvanceToNext() async {
    final grading = context.read<GradingProvider>();
    await _save(silent: true);
    if (!mounted) return;
    if (grading.currentIndex >= grading.students.length - 1) {
      // آخر طالب — ننهي الجلسة ونُفعّل شاشة الاحتفال
      _autoLoopActive = false;
      HapticFeedback.heavyImpact();
      // finishGrading() يرفع علم _gradingFinished → currentStudent يُرجع null
      // → الشرط (cur == null) في build() يُظهر شاشة الاحتفال
      grading.finishGrading();
      if (mounted) setState(() {});
      return;
    }
    grading.nextStudent();
    _resetFieldFocus(toFirstEmpty: true);
    if (mounted) setState(() {});
    _toast('الطالب التالي');
  }

  Future<bool?> _showConfirmDialog() async {
    final grading = context.read<GradingProvider>();
    final cur = grading.currentStudent;
    if (cur == null) return null;
    final totalPossible = grading.fields.fold<double>(0, (s, f) => s + f.max);
    final pct = totalPossible > 0
        ? (cur.total / totalPossible * 100).toStringAsFixed(1)
        : '0';
    final isLast = grading.currentIndex >= grading.students.length - 1;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'تأكيد درجات الطالب',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  cur.name,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      ...grading.fields.map((f) {
                        final v = cur.grades[f.name];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                f.label,
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                v == null
                                    ? '—'
                                    : '${_fmt(v)} / ${_fmt(f.max)}',
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'المجموع',
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_fmt(cur.total)} / ${_fmt(totalPossible)}  ($pct%)',
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: Text(
                          'تعديل',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.warning,
                          side: const BorderSide(color: AppColors.warning),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: Icon(
                          isLast ? Icons.flag_rounded : Icons.arrow_back_rounded,
                          size: 18,
                        ),
                        label: Text(
                          isLast ? 'إنهاء وحفظ' : 'تأكيد والطالب التالي',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text(
                    'إيقاف الوضع التلقائي',
                    style: GoogleFonts.cairo(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =================== Manual mode (legacy / fallback) ===================
  Future<void> _toggleRecord() async {
    HapticFeedback.mediumImpact();

    if (_smartMode) {
      if (_autoLoopActive || voiceService.isListening) {
        await _stopAutoLoop();
      } else {
        await _startAutoLoop();
      }
      return;
    }

    final grading = context.read<GradingProvider>();
    if (voiceService.isListening) {
      await voiceService.stopListening();
      if (mounted) setState(() {});
      return;
    }
    if (voiceService.isRecording) {
      final path = await voiceService.stopRecording();
      if (mounted) setState(() {});
      if (path != null) {
        await _transcribeFile(path);
      }
      return;
    }

    if (mounted) {
      setState(() {
        _transcript = '';
        _justFilledField = null;
      });
    }

    // فرض السقف الإداري: امنع استخدام مسار السيرفر (Whisper AI) إذا
    // كان المطور قد عطّله من إعدادات النظام، حتى لو كان المفتاح المحلي
    // لا يزال مفعّلاً من جلسة سابقة.
    final useServer = _useServerTranscription && _serverSpeechAllowedBySystem;
    if (useServer) {
      try {
        await voiceService.startRecording();
        if (mounted) setState(() {});
      } catch (e) {
        _toast(e.toString(), error: true);
      }
    } else {
      try {
        final text = await voiceService.listenOnce(
          onPartial: (p) {
            if (mounted) setState(() => _transcript = p);
          },
        );
        if (mounted) setState(() {});
        if (text.isNotEmpty) {
          _processVoiceResult(text, grading);
        } else {
          _toast('لم يتم التعرف على أي كلام، حاول مرة أخرى');
        }
      } catch (e) {
        _toast(e.toString(), error: true);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _transcribeFile(String path) async {
    if (mounted) setState(() => _isProcessing = true);
    try {
      final text = await apiClient.transcribeAudio(path);
      if (mounted) setState(() => _transcript = text);
      if (text.isNotEmpty && mounted) {
        _processVoiceResult(text, context.read<GradingProvider>());
      } else {
        _toast('لم يتم التعرف على الصوت');
      }
    } catch (e) {
      _toast('فشل تحويل الصوت: $e', error: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _processVoiceResult(String text, GradingProvider grading) {
    final result = NLPParser.parse(text);
    HapticFeedback.lightImpact();

    if (result.hasNext) {
      _saveAndNext();
      return;
    }
    if (result.hasPrevious) {
      grading.previousStudent();
      _resetFieldFocus(toFirstEmpty: true);
      _toast('الطالب السابق');
      return;
    }
    if (result.hasSave) {
      _save(silent: false);
      return;
    }
    if (result.hasClear) {
      grading.clearCurrentGrades();
      _resetFieldFocus(toFirstEmpty: true);
      _toast('تم مسح الدرجات');
      return;
    }
    if (result.hasAbsent) {
      for (final f in grading.fields) {
        grading.updateGrade(grading.currentIndex, f.name, 0);
      }
      _toast('تم تسجيل الطالب كغائب');
      return;
    }

    if (result.numbers.isNotEmpty) {
      final cur = grading.currentStudent;
      if (cur == null) return;
      final updated = NLPParser.distributeGrades(
        result.numbers,
        grading.fields,
        cur.grades,
      );
      updated.forEach((field, value) {
        grading.updateGrade(grading.currentIndex, field, value);
      });
      if (mounted) {
        setState(() {
          _justFilledField =
              updated.keys.isNotEmpty ? updated.keys.last : null;
        });
      }
      _toast('تم رصد ${result.numbers.length} درجة', success: true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _justFilledField = null);
      });
    } else {
      _toast('لم يتم التعرف على أرقام');
    }
  }

  // =================== Save / Export / Stats ===================
  Future<void> _save({bool silent = false}) async {
    final grading = context.read<GradingProvider>();
    final ok = await grading.saveCurrentStudent();
    if (!mounted) return;
    if (ok) {
      AdminService.trackEvent('grade_synced_online');
      if (!silent) _toast('تم حفظ الدرجات على السيرفر', success: true);
    } else {
      AdminService.trackEvent('grade_saved_locally');
      if (!silent) {
        _toast('تم الحفظ محلياً، سيتم المزامنة تلقائياً عند توفر الإنترنت');
      }
    }
    HapticFeedback.heavyImpact();
  }

  Future<void> _saveAndNext() async {
    await _save(silent: true);
    if (!mounted) return;
    final grading = context.read<GradingProvider>();
    if (grading.currentIndex >= grading.students.length - 1) {
      // آخر طالب — ننهي الجلسة ونُظهر شاشة الاحتفال
      _autoLoopActive = false;
      HapticFeedback.heavyImpact();
      grading.finishGrading();
      if (mounted) setState(() {});
      return;
    }
    grading.nextStudent();
    _resetFieldFocus(toFirstEmpty: true);
    if (mounted) setState(() {});
    _toast('الطالب التالي');
  }

  Future<void> _exportExcel() async {
    final grading = context.read<GradingProvider>();
    final auth = context.read<AuthProvider>();
    if (grading.students.isEmpty) {
      _toast('لا يوجد طلاب للتصدير', error: true);
      return;
    }
    if (_autoLoopActive) await _stopAutoLoop(silent: true);
    // على الويب: يُصدَّر CSV تلقائياً (dart:io غير متاح)
    _toast('جاري إعداد الملف للتصدير...');
    final ok = await AnalyticsService.exportToExcel(
      students: grading.students,
      fields: grading.fields,
      className: widget.className,
      subject: widget.subject,
      teacherName: auth.user?.displayName,
    );
    if (!mounted) return;
    if (!ok) {
      _toast('فشل التصدير — حاول مرة أخرى', error: true);
    } else {
      AdminService.trackEvent('excel_export_completed');
      _toast('تم التصدير بنجاح ✅', success: true);
    }
  }

  void _showStats() {
    final grading = context.read<GradingProvider>();
    final stats = AnalyticsService.calculate(grading.students, grading.fields);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _StatsSheet(stats: stats),
    );
  }

  void _showHelp() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _HelpSheet(),
    );
  }

  // =================== UI ===================
  @override
  Widget build(BuildContext context) {
    final grading = context.watch<GradingProvider>();
    final cur = grading.currentStudent;
    final total = grading.students.length;
    final idx = grading.currentIndex;

    // فرض السقف الإداري: إذا عطّل المطور "الوضع الأوفلاين" من إعدادات
    // النظام، لا يُسمح بمتابعة الرصد بدون اتصال إنترنت فعلي (باستثناء
    // العرض التجريبي الذي لا يعتمد أصلاً على مزامنة حقيقية).
    final blockedByOfflinePolicy = !_offlineModeAllowedBySystem &&
        !grading.isOnline &&
        widget.classId != 0;
    if (blockedByOfflinePolicy) {
      return _buildOfflineBlockedScreen();
    }

    if (cur == null) {
      // حالة: انتهت قائمة الطلاب بالكامل (بعد آخر طالب)
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(22)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        widget.className,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.celebration_rounded,
                            size: 62,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'أحسنت العمل رائعاً! مبروك عليك',
                          style: GoogleFonts.cairo(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'تم الانتهاء من جميع طلاب\n${widget.className} • ${widget.subject}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => DashboardScreen(
                                      className: widget.className,
                                      subject: widget.subject,
                                    ),
                                  ),
                                ),
                                icon: const Icon(
                                    Icons.analytics_rounded,
                                    size: 18),
                                label: Text(
                                  'عرض التحليلات',
                                  style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.bold),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  side: const BorderSide(
                                      color: AppColors.primary),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _exportExcel,
                                icon: const Icon(
                                    Icons.table_chart_rounded,
                                    size: 18),
                                label: Text(
                                  'تصدير Excel',
                                  style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.home_rounded, size: 18),
                          label: Text(
                            'العودة للصفحة الرئيسية',
                            style: GoogleFonts.cairo(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (_autoLoopActive) {
          await _stopAutoLoop(silent: true);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(grading, idx, total),
              if (!grading.isOnline) _offlineBanner(grading.pendingCount),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                  child: Column(
                    children: [
                      _buildStudentCard(cur, grading),
                      const SizedBox(height: 14),
                      _buildVoiceArea(grading),
                      const SizedBox(height: 14),
                      _buildGradeFields(grading, cur),
                    ],
                  ),
                ),
              ),
              _buildBottomBar(grading),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(GradingProvider grading, int idx, int total) {
    final progress = total > 0 ? (idx + 1) / total : 0.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () async {
                  if (_autoLoopActive) await _stopAutoLoop(silent: true);
                  if (mounted) Navigator.pop(context);
                },
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      widget.className,
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.subject,
                      style: GoogleFonts.cairo(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _showHelp,
                tooltip: 'تعليمات',
                icon: const Icon(Icons.help_outline, color: Colors.white),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DashboardScreen(
                      className: widget.className,
                      subject: widget.subject,
                    ),
                  ),
                ),
                tooltip: 'لوحة التحليلات',
                icon: const Icon(
                  Icons.analytics_rounded,
                  color: Colors.white,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StudentsListScreen(
                      className: widget.className,
                      subject: widget.subject,
                    ),
                  ),
                ),
                tooltip: 'قائمة الطلاب',
                icon: const Icon(Icons.list_alt_rounded, color: Colors.white),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  '${idx + 1} / $total',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.cairo(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _offlineBanner(int pending) {
    return Container(
      width: double.infinity,
      color: AppColors.warning.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: AppColors.warning, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pending > 0
                  ? 'وضع أوفلاين • $pending درجة بانتظار المزامنة'
                  : 'وضع أوفلاين • سيتم الحفظ محلياً',
              textAlign: TextAlign.right,
              style: GoogleFonts.cairo(
                fontSize: 11,
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// شاشة تُعرض عندما يكون الجهاز أوفلاين والمطور قد عطّل "الوضع
  /// الأوفلاين" من إعدادات النظام — تمنع الاستمرار في الرصد دون اتصال
  /// حقيقي بدلاً من ترك الإعداد شكلياً بلا أي تأثير فعلي.
  Widget _buildOfflineBlockedScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 50,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'الوضع الأوفلاين غير متاح حالياً',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'قام المطور بتعطيل العمل بدون إنترنت مؤقتاً.\n'
                  'يرجى الاتصال بالإنترنت والمحاولة مرة أخرى.',
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.7,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 26),
                ElevatedButton.icon(
                  onPressed: () async {
                    if (mounted) setState(() {});
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    'إعادة المحاولة',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text('العودة', style: GoogleFonts.cairo()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentCard(dynamic student, GradingProvider g) {
    final totalPossible = g.fields.fold<double>(0, (s, f) => s + f.max);
    final percent = totalPossible > 0
        ? (student.total / totalPossible).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    student.name.isNotEmpty ? student.name[0] : '?',
                    style: GoogleFonts.cairo(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      student.name,
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'رقم الجلوس: ${student.studentNumber}',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  'المجموع',
                  '${_fmt(student.total)} / ${_fmt(totalPossible)}',
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStat(
                  'النسبة',
                  '${(percent * 100).toStringAsFixed(0)}%',
                  percent >= 0.5 ? AppColors.success : AppColors.error,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStat(
                  'البنود المسجلة',
                  '${student.grades.length} / ${g.fields.length}',
                  AppColors.info,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  Widget _buildVoiceArea(GradingProvider grading) {
    final isActive =
        voiceService.isListening || voiceService.isRecording || _autoLoopActive;
    final allFilled = _currentFieldIndex >= grading.fields.length;
    final currentField = (!allFilled && _currentFieldIndex >= 0)
        ? grading.fields[_currentFieldIndex]
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_smartMode && currentField != null)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 14,
              ),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.center_focus_strong_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'البند الحالي: ${currentField.label}  (من ${_fmt(currentField.max)})',
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_smartMode && currentField == null && grading.fields.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 14,
              ),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.success,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'تم رصد جميع البنود — قل "تأكيد" أو اضغط زر التالي',
                    style: GoogleFonts.cairo(
                      color: AppColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          RecordingButton(
            isRecording: isActive,
            isPaused: false,
            isProcessing: _isProcessing,
            onPressed: _toggleRecord,
          ),
          const SizedBox(height: 12),
          Text(
            _isProcessing
                ? 'جاري معالجة الصوت...'
                : isActive
                ? (_smartMode
                      ? '🎤 الوضع التلقائي يعمل... قل الدرجة'
                      : 'استمع... قل الدرجات بالعربية 🎤')
                : (_smartMode
                      ? 'اضغط لبدء الرصد التلقائي السريع'
                      : 'اضغط للبدء بالتسجيل الصوتي'),
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isActive
                  ? AppColors.recordingActive
                  : AppColors.textPrimary,
            ),
          ),
          if (_transcript.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '"$_transcript"',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Switch(
                  value: _smartMode,
                  onChanged: (v) async {
                    if (_autoLoopActive) await _stopAutoLoop(silent: true);
                    setState(() => _smartMode = v);
                  },
                  activeThumbColor: AppColors.success,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _smartMode
                        ? 'الوضع التلقائي الذكي (موصى به)'
                        : 'الوضع اليدوي (تسجيل واحد)',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _smartMode
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_smartMode) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Switch(
                  value: _useServerTranscription &&
                      _serverSpeechAllowedBySystem,
                  onChanged: !_serverSpeechAllowedBySystem
                      ? null
                      : (v) => setState(() => _useServerTranscription = v),
                  activeThumbColor: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  !_serverSpeechAllowedBySystem
                      ? 'السيرفر معطّل حالياً من قِبل المطور'
                      : _useServerTranscription
                          ? 'تحويل عبر السيرفر (Whisper AI)'
                          : 'تحويل على الجهاز (سريع)',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGradeFields(GradingProvider g, dynamic student) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.assignment_outlined,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'بنود التقييم',
                  style: GoogleFonts.cairo(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    g.clearCurrentGrades();
                    _resetFieldFocus(toFirstEmpty: true);
                    _toast('تم مسح الدرجات');
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text('تصفير', style: GoogleFonts.cairo(fontSize: 12)),
                ),
              ],
            ),
          ),
          ...List.generate(g.fields.length, (i) {
            final f = g.fields[i];
            final isCurrent = _smartMode && i == _currentFieldIndex;
            final isJustFilled = _justFilledField == f.name;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _currentFieldIndex = i;
                  _justFilledField = null;
                });
              },
              child: GradeFieldCard(
                field: f,
                value: student.grades[f.name],
                isHighlighted: isCurrent || isJustFilled,
                onChanged: (v) =>
                    g.updateGrade(g.currentIndex, f.name, v),
              ),
            );
          }),
          if (g.fields.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'لا توجد بنود تقييم لهذه المادة',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(color: AppColors.textHint),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(GradingProvider g) {
    final isFirst = g.currentIndex == 0;
    final isLast = g.currentIndex >= g.students.length - 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _navBtn(
              icon: Icons.arrow_forward_rounded,
              label: 'السابق',
              onTap: isFirst
                  ? null
                  : () {
                      g.previousStudent();
                      _resetFieldFocus(toFirstEmpty: true);
                      setState(() {});
                    },
            ),
            const SizedBox(width: 6),
            _circleBtn(
              icon: Icons.bar_chart_rounded,
              tooltip: 'الإحصائيات',
              onTap: _showStats,
              color: AppColors.info,
            ),
            const SizedBox(width: 6),
            _circleBtn(
              icon: Icons.table_chart_rounded,
              tooltip: 'تصدير Excel',
              onTap: _exportExcel,
              color: AppColors.success,
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () => _save(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.save_rounded, size: 18),
                label: Text(
                  'حفظ',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _navBtn(
              icon: Icons.arrow_back_rounded,
              label: 'التالي',
              onTap: isLast ? null : _saveAndNext,
              primary: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
  }) {
    return Expanded(
      flex: 2,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: primary ? AppColors.primary : Colors.grey.shade100,
          foregroundColor: primary ? Colors.white : AppColors.textPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: primary ? 2 : 0,
        ),
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

enum _SmartAction { none, assigned, next, previous, cleared, absent, stop }

class _StatsSheet extends StatelessWidget {
  final ClassStats stats;
  const _StatsSheet({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'إحصائيات الفصل',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.7,
            ),
            children: [
              _statBox('عدد الطلاب', '${stats.totalStudents}',
                  Icons.people_outline, AppColors.primary),
              _statBox('المتوسط', stats.averageScore.toStringAsFixed(1),
                  Icons.trending_up, AppColors.info),
              _statBox(
                'نسبة النجاح',
                '${stats.successRate.toStringAsFixed(0)}%',
                Icons.check_circle_outline,
                AppColors.success,
              ),
              _statBox(
                'نسبة الإنجاز',
                '${stats.completionPercentage.toStringAsFixed(0)}%',
                Icons.task_alt_rounded,
                AppColors.warning,
              ),
              _statBox(
                'أعلى درجة',
                stats.highestScore.toStringAsFixed(1),
                Icons.emoji_events_outlined,
                Colors.amber.shade700,
              ),
              _statBox(
                'أقل درجة',
                stats.lowestScore.toStringAsFixed(1),
                Icons.warning_amber_outlined,
                AppColors.error,
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(
                  Icons.help_outline,
                  color: AppColors.primary,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Text(
                  'دليل الإدخال الصوتي الذكي',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _section(
              '🌟 الوضع التلقائي الذكي',
              '• اضغط زر الميكروفون مرة واحدة لبدء الرصد\n'
                  '• قل الدرجة فقط (مثل: "خمسة عشر") وستُسجّل في البند الحالي\n'
                  '• ينتقل التطبيق آلياً للبند التالي بعد كل رقم\n'
                  '• بعد آخر بند يظهر مربع تأكيد بكامل الدرجات\n'
                  '• اضغط "تأكيد والطالب التالي" أو قل "التالي"\n'
                  '• اضغط الميكروفون مرة أخرى لإيقاف الرصد التلقائي',
              Icons.auto_awesome,
              AppColors.success,
            ),
            _section(
              '🔢 الأرقام',
              'يمكنك قول الأرقام بالعربية الفصحى أو اللهجة المصرية:\n'
                  '• "خمسة عشر" أو "خمستاشر"\n'
                  '• "تلاتة وعشرين" → 23\n'
                  '• "عشرة ونص" → 10.5\n'
                  '• "صفر" → 0\n'
                  '• "كاملة" / "النهاية" → الدرجة الكاملة\n'
                  '• أو قل الرقم مباشرة بالأرقام: "12.5"',
              Icons.format_list_numbered,
              AppColors.primary,
            ),
            _section(
              '🎯 أوامر التنقل',
              '• "التالي" أو "كمل" → ينتقل للطالب التالي\n'
                  '• "السابق" أو "ارجع" → الطالب السابق\n'
                  '• "تأكيد" أو "تمام" → تأكيد الدرجات\n'
                  '• "حفظ" → حفظ وإيقاف الوضع التلقائي\n'
                  '• "امسح" أو "تصفير" → مسح الدرجات\n'
                  '• "غائب" → تسجيل الطالب كغائب\n'
                  '• "إيقاف" → إيقاف الرصد التلقائي',
              Icons.gesture_outlined,
              AppColors.info,
            ),
            _section(
              '📊 تصدير Excel الرسمي',
              'يقوم التطبيق بتصدير ملف Excel احترافي مطابق لورقة الرصد الرسمية:\n'
                  '• اسم المدرسة، الصف، المادة، المعلم، التاريخ\n'
                  '• حدود ملونة وألوان متناوبة للصفوف\n'
                  '• صف الدرجة العظمى لكل بند\n'
                  '• ألوان مختلفة للناجح/الراسب\n'
                  '• إحصائيات الفصل ومناطق التوقيع\n'
                  '• مناسب للطباعة والتسليم الرسمي',
              Icons.table_chart_outlined,
              AppColors.warning,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'فهمت',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String body, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.right,
            style: GoogleFonts.cairo(
              fontSize: 13,
              height: 1.7,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
