import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/error_recovery.dart';
import 'storage_service.dart';
import 'connectivity_service.dart';
import 'admin_service.dart';

/// Comprehensive app initialization service
class AppInitializationService {
  static final AppInitializationService _instance =
      AppInitializationService._internal();

  factory AppInitializationService() {
    return _instance;
  }

  AppInitializationService._internal();

  bool _isInitialized = false;
  final List<String> _initializationLog = [];

  bool get isInitialized => _isInitialized;
  List<String> get initializationLog => List.unmodifiable(_initializationLog);

  /// Initialize all services with comprehensive error handling
  Future<bool> initializeApp() async {
    if (_isInitialized) {
      print('[APP_INIT] App already initialized');
      return true;
    }

    print('[APP_INIT] ========== APP INITIALIZATION START ==========');
    print('[APP_INIT] Timestamp: ${DateTime.now()}');

    try {
      // Step 1: Initialize Storage
      await _initializeStorage();

      // Step 2: Initialize Connectivity
      await _initializeConnectivity();

      // Step 3: Initialize Admin Service
      await _initializeAdminService();

      // Step 4: Verify all services
      await _verifyServices();

      _isInitialized = true;
      print('[APP_INIT] ✓ APP INITIALIZATION COMPLETED SUCCESSFULLY');
      print('[APP_INIT] ========== APP INITIALIZATION END ==========');
      return true;
    } catch (e, s) {
      print('[APP_INIT] ✗ APP INITIALIZATION FAILED: $e');
      print('[APP_INIT] Stack trace: $s');
      errorRecovery.recordError(
        'App initialization failed: $e',
        s,
        context: 'AppInitializationService.initializeApp',
        additionalData: {
          'initializationLog': _initializationLog,
        },
      );
      return false;
    }
  }

  /// Initialize storage service with retry logic
  Future<void> _initializeStorage() async {
    print('[APP_INIT] [1/3] Initializing StorageService...');
    _initializationLog.add('Starting StorageService initialization');

    try {
      await errorRecovery.retryWithBackoff(
        () => StorageService.init().timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            throw TimeoutException('StorageService.init timeout');
          },
        ),
        maxRetries: 2,
        operationName: 'StorageService.init',
      );
      print('[APP_INIT] ✓ StorageService initialized successfully');
      _initializationLog.add('✓ StorageService initialized');
    } catch (e, s) {
      print('[APP_INIT] ✗ StorageService initialization failed: $e');
      _initializationLog.add('✗ StorageService failed: $e');
      errorRecovery.recordError(
        'StorageService initialization failed: $e',
        s,
        context: '_initializeStorage',
      );
      rethrow;
    }
  }

  /// Initialize connectivity service with retry logic
  Future<void> _initializeConnectivity() async {
    print('[APP_INIT] [2/3] Initializing ConnectivityService...');
    _initializationLog.add('Starting ConnectivityService initialization');

    try {
      await errorRecovery.retryWithBackoff(
        () => connectivityService.init().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            throw TimeoutException('ConnectivityService.init timeout');
          },
        ),
        maxRetries: 2,
        operationName: 'ConnectivityService.init',
      );
      print('[APP_INIT] ✓ ConnectivityService initialized successfully');
      _initializationLog.add('✓ ConnectivityService initialized');
    } catch (e, s) {
      print('[APP_INIT] ⚠️ ConnectivityService initialization failed: $e');
      _initializationLog.add('⚠️ ConnectivityService failed (non-critical): $e');
      // Don't rethrow - connectivity is non-critical
      errorRecovery.recordError(
        'ConnectivityService initialization failed (non-critical): $e',
        s,
        context: '_initializeConnectivity',
      );
    }
  }

  /// Initialize admin service with retry logic
  Future<void> _initializeAdminService() async {
    print('[APP_INIT] [3/3] Initializing AdminService...');
    _initializationLog.add('Starting AdminService initialization');

    try {
      await errorRecovery.retryWithBackoff(
        () => AdminService.initDefaultDeveloper().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            throw TimeoutException('AdminService.initDefaultDeveloper timeout');
          },
        ),
        maxRetries: 2,
        operationName: 'AdminService.initDefaultDeveloper',
      );
      print('[APP_INIT] ✓ AdminService initialized successfully');
      _initializationLog.add('✓ AdminService initialized');
    } catch (e, s) {
      print('[APP_INIT] ⚠️ AdminService initialization failed: $e');
      _initializationLog.add('⚠️ AdminService failed (non-critical): $e');
      // Don't rethrow - admin service is non-critical
      errorRecovery.recordError(
        'AdminService initialization failed (non-critical): $e',
        s,
        context: '_initializeAdminService',
      );
    }
  }

  /// Verify all services are working
  Future<void> _verifyServices() async {
    print('[APP_INIT] Verifying services...');
    _initializationLog.add('Verifying services');

    try {
      // Verify storage
      final hasSeenIntro = await StorageService.hasSeenIntro()
          .timeout(const Duration(seconds: 2));
      print('[APP_INIT] ✓ Storage verification: OK');
      _initializationLog.add('✓ Storage verification: OK');

      // Verify connectivity
      final isOnline = connectivityService.isOnline;
      print('[APP_INIT] ✓ Connectivity verification: ${isOnline ? 'Online' : 'Offline'}');
      _initializationLog.add('✓ Connectivity verification: OK');
    } catch (e, s) {
      print('[APP_INIT] ⚠️ Service verification failed: $e');
      _initializationLog.add('⚠️ Service verification failed: $e');
      errorRecovery.recordError(
        'Service verification failed: $e',
        s,
        context: '_verifyServices',
      );
      // Don't rethrow - verification failure is non-critical
    }
  }

  /// Reset initialization state (for testing)
  void reset() {
    _isInitialized = false;
    _initializationLog.clear();
    print('[APP_INIT] Initialization state reset');
  }

  /// Get initialization status report
  String getStatusReport() {
    final buffer = StringBuffer();
    buffer.writeln('=== APP INITIALIZATION STATUS ===');
    buffer.writeln('Initialized: $_isInitialized');
    buffer.writeln('Timestamp: ${DateTime.now()}');
    buffer.writeln('');
    buffer.writeln('Initialization Log:');
    for (final log in _initializationLog) {
      buffer.writeln('  $log');
    }
    return buffer.toString();
  }
}

/// Global instance
final appInitialization = AppInitializationService();
