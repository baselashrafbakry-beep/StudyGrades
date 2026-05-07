import 'dart:async';
import 'package:flutter/material.dart';

/// Comprehensive error recovery system with retry logic and fallback mechanisms
class ErrorRecoveryManager {
  static final ErrorRecoveryManager _instance = ErrorRecoveryManager._internal();

  factory ErrorRecoveryManager() {
    return _instance;
  }

  ErrorRecoveryManager._internal();

  final List<ErrorRecord> _errorHistory = [];
  final int maxHistorySize = 100;

  /// Record an error for analysis
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

    print('[ERROR_RECOVERY] Error recorded: $message');
    print('[ERROR_RECOVERY] Context: $context');
    if (stackTrace != null) {
      print('[ERROR_RECOVERY] Stack trace: $stackTrace');
    }
  }

  /// Retry a function with exponential backoff
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
        print('[RETRY] Attempt $attempt/$maxRetries for $operationName');
        final result = await operation().timeout(
          Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Operation timeout after 10 seconds');
          },
        );
        print('[RETRY] ✓ Success on attempt $attempt for $operationName');
        return result;
      } catch (e, s) {
        print('[RETRY] ✗ Attempt $attempt failed: $e');

        if (attempt >= maxRetries) {
          print('[RETRY] ✗ Max retries reached for $operationName');
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

        print('[RETRY] Waiting ${delay.inMilliseconds}ms before retry...');
        await Future.delayed(delay);
        delay = Duration(
          milliseconds: (delay.inMilliseconds * backoffMultiplier).toInt(),
        );
      }
    }
  }

  /// Execute operation with fallback
  Future<T> executeWithFallback<T>(
    Future<T> Function() primaryOperation,
    Future<T> Function() fallbackOperation, {
    String? operationName,
  }) async {
    try {
      print('[FALLBACK] Attempting primary operation: $operationName');
      return await primaryOperation().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Primary operation timeout');
        },
      );
    } catch (e, s) {
      print('[FALLBACK] ✗ Primary operation failed: $e');
      recordError(
        'Primary operation failed, using fallback: $e',
        s,
        context: 'executeWithFallback',
        additionalData: {'operationName': operationName},
      );

      try {
        print('[FALLBACK] Attempting fallback operation: $operationName');
        return await fallbackOperation().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('Fallback operation timeout');
          },
        );
      } catch (fallbackError, fallbackStack) {
        print('[FALLBACK] ✗ Fallback operation also failed: $fallbackError');
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

  /// Get error history
  List<ErrorRecord> getErrorHistory() => List.unmodifiable(_errorHistory);

  /// Clear error history
  void clearErrorHistory() {
    _errorHistory.clear();
    print('[ERROR_RECOVERY] Error history cleared');
  }

  /// Get recent errors
  List<ErrorRecord> getRecentErrors({int limit = 10}) {
    return _errorHistory.skip((_errorHistory.length - limit).clamp(0, _errorHistory.length)).toList();
  }

  /// Export error report
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

/// Error record for tracking
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
  String toString() => 'ErrorRecord('
      'message: $message, '
      'context: $context, '
      'timestamp: $timestamp'
      ')';
}

/// Global instance accessor
final errorRecovery = ErrorRecoveryManager();

/// Retry extension for Future
extension FutureRetry<T> on Future<T> {
  Future<T> retryWithBackoff({
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 500),
  }) async {
    return errorRecovery.retryWithBackoff(
      () => this,
      maxRetries: maxRetries,
      initialDelay: initialDelay,
    );
  }
}
