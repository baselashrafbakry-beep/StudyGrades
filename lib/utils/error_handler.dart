import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// Production-grade global error handler.
///
/// Captures:
///   - Flutter framework errors (FlutterError.onError)
///   - Async / platform errors (PlatformDispatcher.onError)
///   - Zone errors (runZonedGuarded)
///
/// Logs are emitted with [debugPrint] in debug, and forwarded to
/// [productionLog] in release for future Crashlytics/Sentry integration.
class ErrorHandler {
  ErrorHandler._();

  /// In-memory log buffer for the last N errors (useful for support exports).
  static final List<LoggedError> _buffer = <LoggedError>[];
  static const int _maxBuffer = 50;

  /// Install all global handlers. Call ONCE from main() before runApp().
  static void install() {
    // 1) Flutter framework errors (build, render, gestures...)
    FlutterError.onError = (FlutterErrorDetails details) {
      _record(details.exception, details.stack, source: 'FlutterError');
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };

    // 2) Errors that escape the Flutter framework (async, platform channels)
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      _record(error, stack, source: 'PlatformDispatcher');
      return true; // mark handled to avoid app termination
    };
  }

  /// Wrap [runApp] with this to catch any uncaught zone errors.
  static void runGuarded(void Function() body) {
    runZonedGuarded<void>(body, (error, stack) {
      _record(error, stack, source: 'Zone');
    });
  }

  /// Manually log a caught error (for try/catch blocks).
  static void logError(
    Object error, [
    StackTrace? stack,
    String source = 'Manual',
  ]) {
    _record(error, stack, source: source);
  }

  /// Show a user-friendly toast with the error message.
  static void showUserError(
    Object error, {
    String fallback = 'حدث خطأ غير متوقع، حاول مرة أخرى',
  }) {
    final msg = humanize(error, fallback: fallback);
    Fluttertoast.showToast(
      msg: msg,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red.shade700,
      textColor: Colors.white,
      fontSize: 14,
    );
  }

  /// Convert any error object into a user-friendly Arabic string.
  static String humanize(Object error, {String? fallback}) {
    final raw = error.toString();
    if (raw.isEmpty || raw == 'null') {
      return fallback ?? 'حدث خطأ غير متوقع';
    }

    // Network-related
    if (raw.contains('SocketException') ||
        raw.contains('Failed host lookup') ||
        raw.contains('Network is unreachable')) {
      return 'تعذر الاتصال بالإنترنت، تحقق من اتصالك';
    }
    if (raw.contains('TimeoutException') || raw.contains('timeout')) {
      return 'انتهت مهلة الاتصال، حاول مرة أخرى';
    }
    if (raw.contains('HandshakeException') || raw.contains('CERTIFICATE')) {
      return 'تعذر التحقق من شهادة الأمان للسيرفر';
    }

    // Permission
    if (raw.contains('Permission') || raw.contains('permission')) {
      return 'الصلاحية المطلوبة غير ممنوحة';
    }

    // Format / parsing
    if (raw.contains('FormatException')) {
      return 'صيغة البيانات غير صحيحة';
    }
    if (raw.contains('TypeError') || raw.contains('Null check')) {
      return 'خطأ في معالجة البيانات';
    }

    // File / IO
    if (raw.contains('FileSystemException') || raw.contains('No such file')) {
      return 'تعذر الوصول إلى الملف المطلوب';
    }

    // If the error is already a clean Arabic string (thrown manually), use it
    if (_looksLikeArabic(raw) && raw.length < 200) {
      return raw.replaceFirst('Exception: ', '');
    }

    // Strip technical prefixes
    var cleaned = raw
        .replaceFirst('Exception: ', '')
        .replaceFirst('Error: ', '')
        .replaceFirst('FlutterError: ', '');
    if (cleaned.length > 150) cleaned = '${cleaned.substring(0, 147)}...';
    return cleaned.isEmpty ? (fallback ?? 'حدث خطأ غير متوقع') : cleaned;
  }

  static bool _looksLikeArabic(String s) {
    for (final code in s.runes) {
      if (code >= 0x0600 && code <= 0x06FF) return true;
    }
    return false;
  }

  static void _record(Object error, StackTrace? stack,
      {required String source}) {
    final entry = LoggedError(
      error: error,
      stack: stack,
      source: source,
      timestamp: DateTime.now(),
    );
    _buffer.add(entry);
    if (_buffer.length > _maxBuffer) {
      _buffer.removeAt(0);
    }
    if (kDebugMode) {
      debugPrint('🔴 [$source] $error');
      if (stack != null) debugPrint(stack.toString());
    } else {
      productionLog(entry);
    }
  }

  /// Hook for production crash reporting (Crashlytics/Sentry/custom).
  /// Currently a no-op in release builds; replace when integrating a service.
  static void productionLog(LoggedError entry) {
    // Intentionally silent. Buffered in [_buffer] for in-app support export.
  }

  /// Recent errors (for in-app diagnostics screen / support export).
  static List<Map<String, dynamic>> recentErrors() {
    return _buffer
        .map((e) => {
              'timestamp': e.timestamp.toIso8601String(),
              'source': e.source,
              'error': e.error.toString(),
              'stack': e.stack?.toString().split('\n').take(5).join('\n'),
            })
        .toList();
  }

  static void clearBuffer() => _buffer.clear();
}

class LoggedError {
  final Object error;
  final StackTrace? stack;
  final String source;
  final DateTime timestamp;
  LoggedError({
    required this.error,
    required this.stack,
    required this.source,
    required this.timestamp,
  });
}

/// Custom widget shown when a build error occurs (instead of red error screen).
class FriendlyErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;
  const FriendlyErrorWidget({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1F4E78),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'حدث خطأ مؤقت',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  ErrorHandler.humanize(details.exception),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Strict numeric validation utilities (used for grade input).
class GradeValidator {
  GradeValidator._();

  /// Validate a grade string against [min] and [max].
  /// Returns null if valid, or an Arabic error message otherwise.
  static String? validate(
    String? input, {
    double min = 0,
    required double max,
    bool allowEmpty = true,
  }) {
    if (input == null || input.trim().isEmpty) {
      return allowEmpty ? null : 'هذا الحقل مطلوب';
    }
    final trimmed = input.trim();
    final parsed = double.tryParse(trimmed.replaceAll('٫', '.'));
    if (parsed == null) {
      return 'القيمة المدخلة ليست رقماً صحيحاً';
    }
    if (!parsed.isFinite) {
      return 'القيمة الرقمية غير صحيحة';
    }
    if (parsed < min) {
      return 'لا يمكن أن تكون الدرجة أقل من ${_fmt(min)}';
    }
    if (parsed > max) {
      return 'الدرجة لا يمكن أن تتجاوز ${_fmt(max)}';
    }
    return null;
  }

  /// Sanitize and clamp a numeric value to a valid grade range.
  static double clamp(double value, double max, {double min = 0}) {
    if (!value.isFinite) return min;
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static String _fmt(double n) {
    if (n == n.toInt()) return n.toInt().toString();
    return n.toStringAsFixed(1);
  }
}
