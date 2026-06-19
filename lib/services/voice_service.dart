import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../utils/error_handler.dart';

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

  // Safety timeout timer — stored so it can be cancelled if needed
  Timer? _safetyTimer;

  // Streaming partials for continuous mode
  StreamController<String>? _partialController;
  Stream<String>? get partialStream => _partialController?.stream;

  bool get isListening => _isListening;
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  bool get speechAvailable => _speechAvailable;
  bool get isInitialized => _initialized;

  Future<bool> requestPermissions() async {
    final mic = await Permission.microphone.request();
    return mic.isGranted;
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
        onError: (e) {
          // Don't crash on transient errors. Mark as not listening.
          _isListening = false;
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
    String finalText = '';

    void completeOnce(String txt) {
      if (!completer.isCompleted) {
        _isListening = false;
        _safetyTimer?.cancel();
        _safetyTimer = null;
        completer.complete(txt);
      }
    }

    _isListening = true;
    try {
      await _speech.listen(
        localeId: effectiveLocale,
        listenFor: listenFor,
        pauseFor: pauseFor,
        onResult: (result) {
          finalText = result.recognizedWords;
          if (onPartial != null) onPartial(finalText);
          if (result.finalResult) {
            completeOnce(finalText);
          }
        },
        listenOptions: stt.SpeechListenOptions(
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
    // ألغِ الـ timer أولاً قبل أي عملية أخرى
    _safetyTimer?.cancel();
    _safetyTimer = null;
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
