// اختبار تصنيف أخطاء التعرف الصوتي (Task 2: Voice Engine Robustness)
//
// الهدف: التأكد أن كل رمز خطأ خام يصل من speech_to_text (وتحديداً من
// SpeechToTextPlugin.kt على أندرويد) يُصنَّف بشكل صحيح إلى VoiceErrorType
// المناسب، وأن لكل نوع رسالة عربية غير فارغة يمكن عرضها للمستخدم.
//
// هذا يضمن أن حالات "انقطاع الميكروفون" و"الضوضاء العالية" و"رفض
// الصلاحيات" و"مشاكل الشبكة" يتم التعامل معها جميعاً بدل تجاهلها بصمت
// كما كانت الحالة قبل الإصلاح (onError كان يكتفي بـ _isListening = false
// فقط دون أي تصنيف أو رسالة للمستخدم).
import 'package:flutter_test/flutter_test.dart';
import 'package:study_grades_voice/services/voice_service.dart';

void main() {
  group('classifyVoiceError - تصنيف أخطاء speech_to_text الخام', () {
    test('error_no_match و error_speech_timeout → noSpeechDetected', () {
      expect(
        classifyVoiceError('error_no_match'),
        VoiceErrorType.noSpeechDetected,
      );
      expect(
        classifyVoiceError('error_speech_timeout'),
        VoiceErrorType.noSpeechDetected,
      );
    });

    test(
      'error_audio_error و error_client → audioHardware (انقطاع الميكروفون)',
      () {
        expect(
          classifyVoiceError('error_audio_error'),
          VoiceErrorType.audioHardware,
        );
        expect(
          classifyVoiceError('error_client'),
          VoiceErrorType.audioHardware,
        );
      },
    );

    test('error_permission → permissionDenied', () {
      expect(
        classifyVoiceError('error_permission'),
        VoiceErrorType.permissionDenied,
      );
    });

    test('error_network, error_network_timeout, error_server, '
        'error_server_disconnected → network', () {
      for (final code in [
        'error_network',
        'error_network_timeout',
        'error_server',
        'error_server_disconnected',
      ]) {
        expect(
          classifyVoiceError(code),
          VoiceErrorType.network,
          reason: 'الرمز $code يجب أن يُصنَّف كخطأ شبكة',
        );
      }
    });

    test('error_busy و error_too_many_requests → busy', () {
      expect(classifyVoiceError('error_busy'), VoiceErrorType.busy);
      expect(
        classifyVoiceError('error_too_many_requests'),
        VoiceErrorType.busy,
      );
    });

    test('error_language_not_supported و error_language_unavailable → '
        'languageUnavailable', () {
      expect(
        classifyVoiceError('error_language_not_supported'),
        VoiceErrorType.languageUnavailable,
      );
      expect(
        classifyVoiceError('error_language_unavailable'),
        VoiceErrorType.languageUnavailable,
      );
    });

    test('رمز غير معروف → unknown (لا يُسبب انهياراً)', () {
      expect(
        classifyVoiceError('some_future_error_code_v99'),
        VoiceErrorType.unknown,
      );
      expect(classifyVoiceError(''), VoiceErrorType.unknown);
    });
  });

  group('VoiceErrorType.arabicMessage - رسائل عربية لكل المستخدمين', () {
    test('كل نوع خطأ له رسالة عربية غير فارغة', () {
      for (final type in VoiceErrorType.values) {
        final msg = type.arabicMessage;
        expect(
          msg.isNotEmpty,
          true,
          reason: 'النوع $type يجب أن تكون له رسالة عربية',
        );
      }
    });

    test('رسالة noSpeechDetected تلمّح لمشكلة السماع/الضوضاء', () {
      final msg = VoiceErrorType.noSpeechDetected.arabicMessage;
      expect(msg.contains('سماع'), true);
    });

    test('رسالة audioHardware تلمّح لمشكلة الميكروفون', () {
      final msg = VoiceErrorType.audioHardware.arabicMessage;
      expect(msg.contains('الميكروفون'), true);
    });

    test('رسالة permissionDenied تلمّح للإعدادات', () {
      final msg = VoiceErrorType.permissionDenied.arabicMessage;
      expect(msg.contains('صلاحية') || msg.contains('إعدادات'), true);
    });
  });

  group('MicPermissionResult - قيم واضحة لكل حالة صلاحية', () {
    test(
      'يحتوي على 4 حالات: granted, denied, permanentlyDenied, restricted',
      () {
        expect(MicPermissionResult.values.length, 4);
        expect(
          MicPermissionResult.values,
          containsAll([
            MicPermissionResult.granted,
            MicPermissionResult.denied,
            MicPermissionResult.permanentlyDenied,
            MicPermissionResult.restricted,
          ]),
        );
      },
    );
  });
}
