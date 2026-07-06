import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';
import '../utils/error_handler.dart';

/// نتيجة تفصيلية لطلب صلاحية الميكروفون — تُميّز بين الرفض المؤقت
/// (يمكن إعادة الطلب) والرفض الدائم (يجب التوجيه لإعدادات النظام).
enum MicPermissionResult {
  granted,
  denied,
  permanentlyDenied,
  restricted,
}

/// تصنيف أخطاء التعرف الصوتي إلى فئات مفهومة تُترجَم لرسائل عربية
/// واضحة للمستخدم بدل عرض رمز خطأ تقني غير مفهوم.
enum VoiceErrorType {
  /// لم يُسمع كلام واضح — غالباً بسبب ضوضاء عالية أو صمت أو نطق غير مفهوم
  noSpeechDetected,

  /// خطأ في هاردوير الصوت — غالباً انقطاع الميكروفون أو استخدامه من تطبيق آخر
  audioHardware,

  /// صلاحية الميكروفون مرفوضة على مستوى النظام
  permissionDenied,

  /// مشكلة اتصال بالشبكة (عند استخدام التعرف الصوتي عبر السيرفر)
  network,

  /// المحرك الصوتي مشغول بجلسة أخرى أو طلبات كثيرة جداً
  busy,

  /// اللغة/اللهجة المطلوبة غير مدعومة على هذا الجهاز
  languageUnavailable,

  /// خطأ غير مصنّف
  unknown,
}

/// رسائل عربية جاهزة لعرضها للمستخدم حسب نوع الخطأ.
extension VoiceErrorTypeMessage on VoiceErrorType {
  String get arabicMessage {
    switch (this) {
      case VoiceErrorType.noSpeechDetected:
        return 'لم يتم سماعك بوضوح، حاول التحدث في مكان أهدأ وبصوت أعلى قليلاً';
      case VoiceErrorType.audioHardware:
        return 'تعذّر الوصول إلى الميكروفون، تأكد أنه غير مستخدم في تطبيق آخر وأنه متصل بشكل صحيح';
      case VoiceErrorType.permissionDenied:
        return 'صلاحية الميكروفون مرفوضة، فعّلها من إعدادات الجهاز';
      case VoiceErrorType.network:
        return 'تعذّر الاتصال بالسيرفر لتحويل الصوت، تحقق من الإنترنت';
      case VoiceErrorType.busy:
        return 'المحرك الصوتي مشغول، حاول مرة أخرى خلال لحظات';
      case VoiceErrorType.languageUnavailable:
        return 'اللهجة العربية غير مدعومة على هذا الجهاز، فعّل خدمات Google للتعرف الصوتي';
      case VoiceErrorType.unknown:
        return 'حدث خطأ غير متوقع في التعرف الصوتي، حاول مرة أخرى';
    }
  }
}

/// تصنيف رسالة خطأ speech_to_text الخام (مثل error_no_match، error_busy...)
/// إلى نوع مفهوم يمكن للواجهة التعامل معه برسالة عربية مناسبة.
/// دالة top-level (وليست method) عمداً كي يسهل اختبارها مباشرة بدون
/// الحاجة لإنشاء VoiceService حقيقي (الذي يعتمد على plugins منصّة).
///
/// ملاحظة: على أندرويد كل الأخطاء تصل بعلامة permanent=true من الـ plugin
/// نفسه (وليس من نظام التشغيل)، لذا لا نعتمد على permanent لتفسير الخطورة
/// بل على errorMsg النصي مباشرة.
VoiceErrorType classifyVoiceError(String errorMsg) {
  switch (errorMsg) {
    case 'error_no_match':
    case 'error_speech_timeout':
      // غالباً بسبب ضوضاء عالية تُغرق الصوت، أو صمت تام، أو نطق غير واضح
      return VoiceErrorType.noSpeechDetected;
    case 'error_audio_error':
    case 'error_client':
      // مشكلة في التقاط الصوت من الهاردوير — غالباً انقطاع/عطل الميكروفون
      return VoiceErrorType.audioHardware;
    case 'error_permission':
      return VoiceErrorType.permissionDenied;
    case 'error_network':
    case 'error_network_timeout':
    case 'error_server':
    case 'error_server_disconnected':
      return VoiceErrorType.network;
    case 'error_busy':
    case 'error_too_many_requests':
      return VoiceErrorType.busy;
    case 'error_language_not_supported':
    case 'error_language_unavailable':
      return VoiceErrorType.languageUnavailable;
    default:
      return VoiceErrorType.unknown;
  }
}

/// Voice recording + on-device speech-to-text service.
/// Strategy:
///  1. On-device speech_to_text (Arabic, free, instant) - PRIMARY
///  2. Continuous-listening with partial-result streaming for smart auto mode
///  3. Fallback to recording audio file for server-side Whisper transcription
class VoiceService {
  final AudioRecorder _recorder = AudioRecorder();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechAvailable = false;
  bool _initialized = false;
  bool _isListening = false;
  String? _currentRecordingPath;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _disposed = false; // حماية من race condition بعد dispose

  // Safety timeout timer — stored so it can be cancelled if needed
  Timer? _safetyTimer;
  // الـ Completer النشط — يُلغى فوراً عند dispose لمنع تعليق المستدعي
  Completer<String>? _activeCompleter;

  // Streaming partials for continuous mode
  StreamController<String>? _partialController;
  Stream<String>? get partialStream => _partialController?.stream;

  bool get isListening => _isListening;
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  bool get speechAvailable => _speechAvailable;
  bool get isInitialized => _initialized;

  // آخر خطأ صوتي مُصنَّف — يمكن لواجهة المستخدم قراءته بعد initSpeech()
  // أو أثناء الاستماع لعرض رسالة عربية مناسبة (ضوضاء عالية / انقطاع الميكروفون...).
  VoiceErrorType? _lastErrorType;
  VoiceErrorType? get lastErrorType => _lastErrorType;

  // استدعاء اختياري تُبلَّغ به الواجهة فور وقوع خطأ أثناء التعرف الصوتي
  // (مفيد لعرض SnackBar/Toast فوري بدل انتظار نهاية الجلسة).
  void Function(VoiceErrorType type, String rawMessage)? onVoiceError;

  /// طلب صلاحية الميكروفون مع تمييز دقيق بين:
  /// - granted: مُنحت الصلاحية
  /// - denied: رُفضت لكن يمكن إعادة الطلب لاحقاً
  /// - permanentlyDenied: رُفضت نهائياً (المستخدم اختار "عدم السؤال مجدداً")
  ///   ولا يمكن إعادة الطلب برمجياً — يجب توجيه المستخدم لإعدادات النظام
  ///   عبر openAppSettings().
  /// - restricted/limited: قيود على مستوى النظام (نادر على أندرويد، أكثر شيوعاً على iOS)
  Future<MicPermissionResult> requestMicPermission() async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return MicPermissionResult.granted;

    // لا تطلب مجدداً إذا كانت مرفوضة نهائياً — iOS/Android يتجاهلان الطلب
    // في هذه الحالة، والطلب المتكرر قد يُخفي حالة "مرفوض دائماً" الحقيقية.
    if (status.isPermanentlyDenied) {
      return MicPermissionResult.permanentlyDenied;
    }

    status = await Permission.microphone.request();
    if (status.isGranted) return MicPermissionResult.granted;
    if (status.isPermanentlyDenied) {
      return MicPermissionResult.permanentlyDenied;
    }
    if (status.isRestricted || status.isLimited) {
      return MicPermissionResult.restricted;
    }
    return MicPermissionResult.denied;
  }

  /// دالة توافقية قديمة (bool فقط) — أُبقيت لعدم كسر أي استدعاء قديم،
  /// لكن يُفضّل استخدام requestMicPermission() للحصول على تفاصيل أدق.
  Future<bool> requestPermissions() async {
    final result = await requestMicPermission();
    return result == MicPermissionResult.granted;
  }

  /// فتح إعدادات النظام مباشرة لتمكين المستخدم من منح صلاحية الميكروفون
  /// يدوياً بعد الرفض الدائم (permanentlyDenied).
  Future<bool> openSystemSettings() async {
    try {
      return await openAppSettings();
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'VoiceService.openSystemSettings');
      return false;
    }
  }

  /// Initialize the speech recognizer once. Subsequent calls are no-ops.
  /// يُجرّب ar_EG أولاً ثم ar_SA ثم ar كـ fallback.
  Future<bool> initSpeech() async {
    if (_initialized && _speechAvailable) return true;
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (s) {
          // 'listening' / 'notListening' / 'done'
          if (s == 'done' || s == 'notListening') {
            _isListening = false;
          }
        },
        onError: (SpeechRecognitionError e) {
          // لا تنهار على أخطاء عابرة، لكن صنّف الخطأ وأبلغ الواجهة به
          // حتى تعرض رسالة عربية دقيقة (ضوضاء/انقطاع ميكروفون/صلاحيات...).
          _isListening = false;
          _lastErrorType = classifyVoiceError(e.errorMsg);
          try {
            onVoiceError?.call(_lastErrorType!, e.errorMsg);
          } catch (_) {
            // تجاهل أي خطأ من الـ callback الخارجي كي لا يُسقط الخدمة
          }
          // أنهِ أي جلسة استماع نشطة فوراً بدل الانتظار حتى safety timeout —
          // هذا يجعل الواجهة تستجيب مباشرة (خصوصاً في حالة انقطاع الميكروفون
          // أو ضوضاء عالية جداً بدل تجميد الشاشة لثوانٍ إضافية بلا داعٍ).
          _safetyTimer?.cancel();
          _safetyTimer = null;
          if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
            final c = _activeCompleter!;
            _activeCompleter = null;
            c.complete('');
          }
        },
        debugLogging: false,
      );
      _initialized = true;
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'VoiceService.initSpeech');
      _speechAvailable = false;
      _initialized = true;
    }
    return _speechAvailable;
  }

  /// اختيار أفضل locale عربي متاح على الجهاز.
  /// يُعطي الأولوية لـ ar_EG ثم ar_SA ثم أي ar_XX ثم ar.
  Future<String> _bestArabicLocale() async {
    try {
      final locales = await _speech.locales();
      final ids = locales.map((l) => l.localeId).toList();
      const preferred = ['ar_EG', 'ar_SA', 'ar_AE', 'ar_KW', 'ar'];
      for (final loc in preferred) {
        if (ids.contains(loc)) return loc;
      }
      // أي locale يبدأ بـ 'ar'
      final arAny = ids.firstWhere(
        (id) => id.toLowerCase().startsWith('ar'),
        orElse: () => 'ar_EG',
      );
      return arAny;
    } catch (_) {
      return 'ar_EG';
    }
  }

  /// Listen ONCE — returns full transcript when speech ends or timeout fires.
  /// Optionally streams partials via [onPartial].
  Future<String> listenOnce({
    String? localeId, // null = اختيار تلقائي لأفضل locale عربي
    Duration listenFor = const Duration(seconds: 12),
    Duration pauseFor = const Duration(seconds: 3),
    void Function(String partial)? onPartial,
  }) async {
    // حماية: لا تبدأ إذا تمّ dispose بالفعل
    if (_disposed) return '';
    if (!_speechAvailable) {
      final ok = await initSpeech();
      if (!ok) throw 'التعرف الصوتي غير متاح على هذا الجهاز';
    }

    // Make sure no previous session is still alive
    if (_isListening) {
      try {
        await _speech.stop();
      } catch (e, st) {
        ErrorHandler.logError(e, st, 'VoiceService.stopBefore');
      }
      _isListening = false;
      // tiny delay so platform releases mic
      await Future.delayed(const Duration(milliseconds: 120));
    }

    // ألغِ أي timer سابق قبل البدء
    _safetyTimer?.cancel();
    _safetyTimer = null;

    // اختيار أفضل locale متاح إذا لم يُحدَّد
    final effectiveLocale = localeId ?? await _bestArabicLocale();

    final completer = Completer<String>();
    _activeCompleter = completer;
    String finalText = '';

    void completeOnce(String txt) {
      if (!completer.isCompleted) {
        _isListening = false;
        _safetyTimer?.cancel();
        _safetyTimer = null;
        _activeCompleter = null;
        completer.complete(txt);
      }
    }

    _isListening = true;
    try {
      await _speech.listen(
        onResult: (result) {
          finalText = result.recognizedWords;
          if (onPartial != null) onPartial(finalText);
          if (result.finalResult) {
            completeOnce(finalText);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: effectiveLocale,
          listenFor: listenFor,
          pauseFor: pauseFor,
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
    } catch (e) {
      _isListening = false;
      _safetyTimer?.cancel();
      _safetyTimer = null;
      if (!completer.isCompleted) completer.completeError(e.toString());
      return completer.future;
    }

    // Safety timeout — قابل للإلغاء لمنع memory leak بعد dispose
    _safetyTimer = Timer(listenFor + const Duration(seconds: 1), () async {
      if (!completer.isCompleted) {
        try {
          await _speech.stop();
        } catch (e, st) {
          ErrorHandler.logError(e, st, 'VoiceService.timeoutStop');
        }
        completeOnce(finalText);
      }
    });

    return completer.future;
  }

  Future<void> stopListening() async {
    if (_isListening) {
      try {
        await _speech.stop();
      } catch (e, st) {
        ErrorHandler.logError(e, st, 'VoiceService.stopListening');
      }
      _isListening = false;
    }
  }

  Future<void> cancelListening() async {
    // ألغِ timeout timer أولاً لمنع استدعاء _speech.stop بعد dispose
    _safetyTimer?.cancel();
    _safetyTimer = null;

    if (_isListening) {
      try {
        await _speech.cancel();
      } catch (e, st) {
        ErrorHandler.logError(e, st, 'VoiceService.cancelListening');
      }
      _isListening = false;
    }
    // also clean up any continuous streams
    await _partialController?.close();
    _partialController = null;
  }

  // ============ File Recording (for server-side Whisper) ============
  Future<String> startRecording() async {
    if (!await _recorder.hasPermission()) {
      // تحقّق من حالة الصلاحية الدقيقة لإعطاء المستخدم رسالة قابلة للتصرف
      final status = await Permission.microphone.status;
      if (status.isPermanentlyDenied) {
        throw 'صلاحية الميكروفون مرفوضة نهائياً، افتح إعدادات التطبيق لتفعيلها';
      }
      throw 'صلاحية الميكروفون مرفوضة';
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(
      dir.path,
      'rec_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );
    _currentRecordingPath = path;
    _isRecording = true;
    _isPaused = false;
    return path;
  }

  Future<void> pauseRecording() async {
    if (_isRecording && !_isPaused) {
      await _recorder.pause();
      _isPaused = true;
    }
  }

  Future<void> resumeRecording() async {
    if (_isRecording && _isPaused) {
      await _recorder.resume();
      _isPaused = false;
    }
  }

  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'VoiceService.stopRecording');
    }
    _isRecording = false;
    _isPaused = false;
    final result = path ?? _currentRecordingPath;
    _currentRecordingPath = null;
    return result;
  }

  Future<void> dispose() async {
    _disposed = true;
    // ألغِ الـ timer أولاً قبل أي عملية أخرى
    _safetyTimer?.cancel();
    _safetyTimer = null;
    // أكمل أي completer معلّق لمنع تعليق المستدعي إلى الأبد
    if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
      _activeCompleter!.complete('');
      _activeCompleter = null;
    }
    try {
      await cancelListening();
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'VoiceService.disposeCancel');
    }
    try {
      await _recorder.dispose();
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'VoiceService.disposeRecorder');
    }
  }
}

final voiceService = VoiceService();
