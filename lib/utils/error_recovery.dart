import 'dart:async';
import 'package:flutter/foundation.dart';

/// نظام استعادة الأخطاء مع منطق إعادة المحاولة وآليات الاحتياطي
class ErrorRecoveryManager {
  static final ErrorRecoveryManager _instance =
      ErrorRecoveryManager._internal();

  factory ErrorRecoveryManager() => _instance;

  ErrorRecoveryManager._internal();

  final List<ErrorRecord> _errorHistory = [];
  final int maxHistorySize = 100;

  /// تسجيل خطأ للتحليل
  void recordError(
    String message,
    StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? additionalData,
  }) {
    final record = ErrorRecord(
      message: message,
      stackTrace: stackTrace,
      context: context,
      timestamp: DateTime.now(),
      additionalData: additionalData,
    );

    _errorHistory.add(record);
    if (_errorHistory.length > maxHistorySize) {
      _errorHistory.removeAt(0);
    }

    if (kDebugMode) {
      debugPrint('[ERROR_RECOVERY] Error recorded: $message');
      debugPrint('[ERROR_RECOVERY] Context: $context');
      if (stackTrace != null) {
        debugPrint(
          '[ERROR_RECOVERY] Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}',
        );
      }
    }
  }

  /// إعادة محاولة دالة مع تأخير تصاعدي (Exponential Backoff)
  Future<T> retryWithBackoff<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 500),
    double backoffMultiplier = 2.0,
    String? operationName,
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (true) {
      try {
        attempt++;
        if (kDebugMode) {
          debugPrint('[RETRY] Attempt $attempt/$maxRetries for $operationName');
        }
        final result = await operation().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Operation timeout after 10 seconds');
          },
        );
        if (kDebugMode) {
          debugPrint(
            '[RETRY] ✓ Success on attempt $attempt for $operationName',
          );
        }
        return result;
      } catch (e, s) {
        if (kDebugMode) {
          debugPrint('[RETRY] ✗ Attempt $attempt failed: $e');
        }

        if (attempt >= maxRetries) {
          if (kDebugMode) {
            debugPrint('[RETRY] ✗ Max retries reached for $operationName');
          }
          recordError(
            'Operation failed after $maxRetries attempts: $e',
            s,
            context: 'retryWithBackoff',
            additionalData: {
              'operationName': operationName,
              'maxRetries': maxRetries,
              'finalAttempt': attempt,
            },
          );
          rethrow;
        }

        if (kDebugMode) {
          debugPrint(
            '[RETRY] Waiting ${delay.inMilliseconds}ms before retry...',
          );
        }
        await Future.delayed(delay);
        delay = Duration(
          milliseconds: (delay.inMilliseconds * backoffMultiplier).toInt(),
        );
      }
    }
  }

  /// تنفيذ عملية مع وضع احتياطي
  Future<T> executeWithFallback<T>(
    Future<T> Function() primaryOperation,
    Future<T> Function() fallbackOperation, {
    String? operationName,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('[FALLBACK] Attempting primary operation: $operationName');
      }
      return await primaryOperation().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Primary operation timeout');
        },
      );
    } catch (e, s) {
      if (kDebugMode) {
        debugPrint('[FALLBACK] ✗ Primary operation failed: $e');
      }
      recordError(
        'Primary operation failed, using fallback: $e',
        s,
        context: 'executeWithFallback',
        additionalData: {'operationName': operationName},
      );

      try {
        if (kDebugMode) {
          debugPrint(
            '[FALLBACK] Attempting fallback operation: $operationName',
          );
        }
        return await fallbackOperation().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('Fallback operation timeout');
          },
        );
      } catch (fallbackError, fallbackStack) {
        if (kDebugMode) {
          debugPrint('[FALLBACK] ✗ Fallback also failed: $fallbackError');
        }
        recordError(
          'Both primary and fallback operations failed: $fallbackError',
          fallbackStack,
          context: 'executeWithFallback_fallback',
          additionalData: {'operationName': operationName},
        );
        rethrow;
      }
    }
  }

  List<ErrorRecord> getErrorHistory() => List.unmodifiable(_errorHistory);

  void clearErrorHistory() {
    _errorHistory.clear();
    if (kDebugMode) debugPrint('[ERROR_RECOVERY] Error history cleared');
  }

  List<ErrorRecord> getRecentErrors({int limit = 10}) {
    return _errorHistory
        .skip((_errorHistory.length - limit).clamp(0, _errorHistory.length))
        .toList();
  }

  String exportErrorReport() {
    final buffer = StringBuffer();
    buffer.writeln('=== ERROR REPORT ===');
    buffer.writeln('Generated: ${DateTime.now()}');
    buffer.writeln('Total Errors: ${_errorHistory.length}');
    buffer.writeln('');
    for (final record in _errorHistory.take(50)) {
      buffer.writeln('---');
      buffer.writeln('Time: ${record.timestamp}');
      buffer.writeln('Context: ${record.context}');
      buffer.writeln('Message: ${record.message}');
      if (record.additionalData != null) {
        buffer.writeln('Data: ${record.additionalData}');
      }
      buffer.writeln('');
    }
    return buffer.toString();
  }
}

class ErrorRecord {
  final String message;
  final StackTrace? stackTrace;
  final String? context;
  final DateTime timestamp;
  final Map<String, dynamic>? additionalData;

  ErrorRecord({
    required this.message,
    this.stackTrace,
    this.context,
    required this.timestamp,
    this.additionalData,
  });

  @override
  String toString() =>
      'ErrorRecord(message: $message, context: $context, timestamp: $timestamp)';
}

/// المثيل العام
final errorRecovery = ErrorRecoveryManager();
