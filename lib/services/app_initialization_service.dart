import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/error_recovery.dart';
import 'storage_service.dart';
import 'connectivity_service.dart';
import 'admin_service.dart';

/// خدمة تهيئة التطبيق الشاملة
class AppInitializationService {
  static final AppInitializationService _instance =
      AppInitializationService._internal();

  factory AppInitializationService() => _instance;

  AppInitializationService._internal();

  bool _isInitialized = false;
  final List<String> _initializationLog = [];

  bool get isInitialized => _isInitialized;
  List<String> get initializationLog => List.unmodifiable(_initializationLog);

  Future<bool> initializeApp() async {
    if (_isInitialized) {
      if (kDebugMode) debugPrint('[APP_INIT] Already initialized');
      return true;
    }

    if (kDebugMode) {
      debugPrint('[APP_INIT] ====== APP INITIALIZATION START ======');
    }

    try {
      await _initializeStorage();
      await _initializeConnectivity();
      await _initializeAdminService();
      await _verifyServices();

      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('[APP_INIT] ✓ INITIALIZATION COMPLETED SUCCESSFULLY');
      }
      return true;
    } catch (e, s) {
      if (kDebugMode) debugPrint('[APP_INIT] ✗ INITIALIZATION FAILED: $e');
      errorRecovery.recordError(
        'App initialization failed: $e',
        s,
        context: 'AppInitializationService.initializeApp',
        additionalData: {'initializationLog': _initializationLog},
      );
      return false;
    }
  }

  Future<void> _initializeStorage() async {
    if (kDebugMode) debugPrint('[APP_INIT] [1/3] StorageService...');
    _initializationLog.add('Starting StorageService initialization');

    try {
      await errorRecovery.retryWithBackoff(
        () => StorageService.init().timeout(
          const Duration(seconds: 4),
          onTimeout: () =>
              throw TimeoutException('StorageService.init timeout'),
        ),
        maxRetries: 2,
        operationName: 'StorageService.init',
      );
      _initializationLog.add('✓ StorageService initialized');
    } catch (e, s) {
      _initializationLog.add('✗ StorageService failed: $e');
      errorRecovery.recordError(
        'StorageService initialization failed: $e',
        s,
        context: '_initializeStorage',
      );
      rethrow;
    }
  }

  Future<void> _initializeConnectivity() async {
    if (kDebugMode) debugPrint('[APP_INIT] [2/3] ConnectivityService...');
    _initializationLog.add('Starting ConnectivityService initialization');

    try {
      await errorRecovery.retryWithBackoff(
        () => connectivityService.init().timeout(
          const Duration(seconds: 3),
          onTimeout: () =>
              throw TimeoutException('ConnectivityService.init timeout'),
        ),
        maxRetries: 2,
        operationName: 'ConnectivityService.init',
      );
      _initializationLog.add('✓ ConnectivityService initialized');
    } catch (e, s) {
      _initializationLog.add('⚠️ ConnectivityService failed (non-critical): $e');
      // لا نُوقف التطبيق - الاتصال غير حيوي
      errorRecovery.recordError(
        'ConnectivityService initialization failed (non-critical): $e',
        s,
        context: '_initializeConnectivity',
      );
    }
  }

  Future<void> _initializeAdminService() async {
    if (kDebugMode) debugPrint('[APP_INIT] [3/3] AdminService...');
    _initializationLog.add('Starting AdminService initialization');

    try {
      await errorRecovery.retryWithBackoff(
        () => AdminService.initDefaultDeveloper().timeout(
          const Duration(seconds: 3),
          onTimeout: () =>
              throw TimeoutException('AdminService.initDefaultDeveloper timeout'),
        ),
        maxRetries: 2,
        operationName: 'AdminService.initDefaultDeveloper',
      );
      _initializationLog.add('✓ AdminService initialized');
    } catch (e, s) {
      _initializationLog.add('⚠️ AdminService failed (non-critical): $e');
      errorRecovery.recordError(
        'AdminService initialization failed (non-critical): $e',
        s,
        context: '_initializeAdminService',
      );
    }
  }

  Future<void> _verifyServices() async {
    if (kDebugMode) debugPrint('[APP_INIT] Verifying services...');
    _initializationLog.add('Verifying services');

    try {
      await StorageService.hasSeenIntro().timeout(const Duration(seconds: 2));
      final isOnline = connectivityService.isOnline;
      _initializationLog.add(
          '✓ Verification OK (${isOnline ? "Online" : "Offline"})');
    } catch (e, s) {
      _initializationLog.add('⚠️ Verification failed: $e');
      errorRecovery.recordError(
        'Service verification failed: $e',
        s,
        context: '_verifyServices',
      );
    }
  }

  void reset() {
    _isInitialized = false;
    _initializationLog.clear();
  }

  String getStatusReport() {
    final buffer = StringBuffer();
    buffer.writeln('=== APP INITIALIZATION STATUS ===');
    buffer.writeln('Initialized: $_isInitialized');
    buffer.writeln('Timestamp: ${DateTime.now()}');
    buffer.writeln('');
    buffer.writeln('Log:');
    for (final log in _initializationLog) {
      buffer.writeln('  $log');
    }
    return buffer.toString();
  }
}

/// المثيل العام
final appInitialization = AppInitializationService();
