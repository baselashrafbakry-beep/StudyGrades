import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../models/subscription_model.dart';
import '../models/user_model.dart';
import '../models/hierarchy_model.dart';
import '../models/student_model.dart';
import '../utils/error_handler.dart';
import 'auth_session_epoch.dart';
import 'sync_request_identity.dart';

class NetworkAuthException implements Exception {
  final String message;

  const NetworkAuthException(this.message);

  @override
  String toString() => message;
}

/// API Client for StudyGrades 2026 backend (deployed on Netlify Functions).
/// Handles JWT auth, automatic token refresh on 401, idempotent retry on
/// transient network errors, and multipart audio uploads for voice
/// transcription.
class ApiClient {
  /// Base URL — overridable at compile time via `--dart-define=API_BASE_URL=...`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://studygrades-2026.netlify.app/api/mobile',
  );

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _userKey = 'cached_user';
  static const _deviceKey = 'installation_device_id';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late final Dio _dio;
  late final Dio _authDio;
  late final Dio _refreshDio;
  Future<String?>? _refreshFuture;
  int? _refreshFutureEpoch;
  final AuthSessionEpoch _sessionEpoch = AuthSessionEpoch();

  @visibleForTesting
  void debugSetHttpClientAdapter(HttpClientAdapter adapter) {
    _dio.httpClientAdapter = adapter;
    _refreshDio.httpClientAdapter = adapter;
  }

  @visibleForTesting
  Future<void> debugSeedAuthSession({
    required String access,
    required String refresh,
    required User user,
  }) async {
    _sessionEpoch.advance();
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
  }

  ApiClient() {
    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      headers: {'Accept': 'application/json'},
    );
    _dio = Dio(options);
    _authDio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        headers: {'Accept': 'application/json'},
      ),
    );
    _refreshDio = Dio(options);

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.extra['_authSessionEpoch'] ??= _sessionEpoch.capture();
          options.headers['X-Device-ID'] = await _deviceId();
          final token = await _storage.read(key: _accessKey);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (e, handler) async {
          // 401 -> try refresh once and replay the original request
          if (e.response?.statusCode == 401 &&
              e.requestOptions.extra['_authSessionEpoch'] ==
                  _sessionEpoch.capture() &&
              e.requestOptions.extra['_skipAuthRefresh'] != true &&
              e.requestOptions.path != '/token/refresh/' &&
              e.requestOptions.path != '/login/' &&
              e.requestOptions.extra['_retried'] != true) {
            try {
              final newToken = await _refreshAccessToken();
              if (newToken != null) {
                final opts = e.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newToken';
                opts.extra['_retried'] = true;
                try {
                  final cloneResp = await _dio.fetch(opts);
                  return handler.resolve(cloneResp);
                } on DioException catch (replayError) {
                  if ((replayError.response?.statusCode == 401 ||
                          replayError.response?.statusCode == 403) &&
                      opts.extra['_authSessionEpoch'] ==
                          _sessionEpoch.capture()) {
                    await clearTokens();
                  }
                  return handler.next(replayError);
                }
              }
            } catch (refreshError, st) {
              ErrorHandler.logError(refreshError, st, 'ApiClient.refreshRetry');
              if (refreshError is DioException &&
                  (refreshError.response?.statusCode == 401 ||
                      refreshError.response?.statusCode == 403) &&
                  e.requestOptions.extra['_authSessionEpoch'] ==
                      _sessionEpoch.capture()) {
                await clearTokens();
              }
            }
          }
          handler.next(e);
        },
      ),
    );
  }

  Future<String> _deviceId() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null &&
        RegExp(r'^[A-Za-z0-9._:-]{8,128}$').hasMatch(existing)) {
      return existing;
    }
    final generated = const Uuid().v4();
    await _storage.write(key: _deviceKey, value: generated);
    return generated;
  }

  Future<String?> _refreshAccessToken() async {
    final refreshEpoch = _sessionEpoch.capture();
    if (_refreshFuture != null && _refreshFutureEpoch == refreshEpoch) {
      return _refreshFuture;
    }
    late final Future<String?> operation;
    operation = (() async {
      try {
        final refresh = await _storage.read(key: _refreshKey);
        if (refresh == null || refresh.isEmpty) {
          if (_sessionEpoch.isCurrent(refreshEpoch)) {
            await clearTokens();
          }
          return null;
        }
        final resp = await _refreshDio.post(
          '/token/refresh/',
          data: {'refresh': refresh},
          options: Options(headers: {'Content-Type': 'application/json'}),
        );
        final newAccess = resp.data['access']?.toString();
        if (newAccess != null && _sessionEpoch.isCurrent(refreshEpoch)) {
          await _storage.write(key: _accessKey, value: newAccess);
          final rotatedRefresh = resp.data['refresh']?.toString();
          if (rotatedRefresh != null && rotatedRefresh.isNotEmpty) {
            await _storage.write(key: _refreshKey, value: rotatedRefresh);
          }
          return newAccess;
        }
      } on DioException catch (e, st) {
        ErrorHandler.logError(e, st, 'ApiClient.refreshAccessToken');
        final code = e.response?.statusCode;
        if ((code == 401 || code == 403) &&
            _sessionEpoch.isCurrent(refreshEpoch)) {
          await clearTokens();
        }
        return null;
      } catch (e, st) {
        ErrorHandler.logError(e, st, 'ApiClient.refreshAccessToken');
        return null;
      } finally {
        if (identical(_refreshFuture, operation)) {
          _refreshFuture = null;
          _refreshFutureEpoch = null;
        }
      }
      return null;
    })();
    _refreshFuture = operation;
    _refreshFutureEpoch = refreshEpoch;
    return operation;
  }

  /// Generic exponential-backoff retry for idempotent requests
  /// (GET, idempotent POSTs like sync).
  Future<T> _withRetry<T>(
    Future<T> Function() task, {
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 600),
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        return await task();
      } on DioException catch (e) {
        // Only retry transient errors
        final transient =
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.connectionError ||
            (e.response?.statusCode != null && e.response!.statusCode! >= 500);
        if (!transient || attempt >= maxAttempts) rethrow;
        await Future.delayed(baseDelay * attempt);
      }
    }
  }

  // ============ AUTH ============
  Future<Map<String, dynamic>> login(String username, String password) async {
    Response? resp;
    final endpoints = ['/token/', '/login/', '/auth/login/'];
    DioException? lastErr;
    final cancelToken = CancelToken();
    final stopwatch = Stopwatch()..start();
    const authenticationDeadline = Duration(seconds: 20);

    for (final ep in endpoints) {
      final remaining = authenticationDeadline - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        cancelToken.cancel('Authentication deadline exceeded');
        throw _authenticationTimeout();
      }
      try {
        resp = await _authDio
            .post(
              ep,
              data: {'username': username, 'password': password},
              options: Options(
                headers: {
                  'Content-Type': 'application/json',
                  'X-Device-ID': await _deviceId(),
                },
              ),
              cancelToken: cancelToken,
            )
            .timeout(
              remaining,
              onTimeout: () {
                cancelToken.cancel('Authentication deadline exceeded');
                throw _authenticationTimeout();
              },
            );
        break;
      } on DioException catch (e) {
        lastErr = e;
        if (e.response?.statusCode == 401 || e.response?.statusCode == 400) {
          throw _formatError(e);
        }
        if (_isNetworkException(e)) {
          break;
        }
        // 404 / 405 -> try next endpoint
      }
    }

    if (resp == null) {
      final error = lastErr;
      if (error == null) {
        throw const NetworkAuthException('تعذر الاتصال بخدمة تسجيل الدخول.');
      }
      final message = _formatError(error);
      if (_isNetworkException(error)) {
        throw NetworkAuthException(message);
      }
      throw message;
    }

    final data = Map<String, dynamic>.from(resp.data);
    final access = data['access']?.toString();
    final refresh = data['refresh']?.toString();
    if (access == null || refresh == null) {
      throw 'استجابة غير متوقعة من السيرفر';
    }
    User user;
    if (data['user'] is Map) {
      final userJson = Map<String, dynamic>.from(data['user']);
      _mergeSubscriptionFields(data, userJson);
      user = User.fromJson(userJson);
    } else {
      final userJson = <String, dynamic>{
        'id': 0,
        'username': username,
        'email': '',
        'role': 'teacher',
      };
      _mergeSubscriptionFields(data, userJson);
      user = User.fromJson(userJson);
    }
    _sessionEpoch.advance();
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    return {'user': user, 'access': access, 'refresh': refresh};
  }

  NetworkAuthException _authenticationTimeout() {
    return const NetworkAuthException(
      'تعذر الاتصال بالخادم خلال المهلة المحددة. '
      'تحقق من الاتصال بالإنترنت وحاول مرة أخرى.',
    );
  }

  Future<void> logout() async {
    try {
      await _dio.post('/logout/');
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'ApiClient.logout');
    }
    await clearTokens();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.post(
        '/account/password/',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          extra: {'_skipAuthRefresh': true},
        ),
      );
      await clearTokens();
    } on DioException catch (e) {
      throw _formatError(e);
    }
  }

  Future<Uri> createBillingCheckout({
    required String plan,
    required String billingCycle,
  }) async {
    try {
      final resp = await _dio.post(
        '/billing/intention/',
        data: {'plan': plan, 'billing_cycle': billingCycle},
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final rawUrl = resp.data is Map
          ? (resp.data['checkout_url']?.toString() ?? '')
          : '';
      final url = Uri.tryParse(rawUrl);
      if (url == null || !url.hasScheme || url.host.isEmpty) {
        throw 'استجابة الدفع غير مكتملة من السيرفر';
      }
      return url;
    } on DioException catch (e) {
      throw _formatError(e);
    }
  }

  Future<User> getCurrentUser() async {
    try {
      final resp = await _dio.get('/account/me/');
      final data = resp.data is Map<String, dynamic>
          ? Map<String, dynamic>.from(resp.data)
          : <String, dynamic>{};
      final rawUser = data['user'];
      if (rawUser is! Map) {
        throw 'استجابة الحساب غير مكتملة من السيرفر';
      }
      final userJson = Map<String, dynamic>.from(rawUser);
      _mergeSubscriptionFields(data, userJson);
      final user = User.fromJson(userJson);
      await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
      return user;
    } on DioException catch (e) {
      throw _formatError(e);
    }
  }

  Future<List<User>> adminListUsers() async {
    try {
      final resp = await _dio.get('/admin/users/');
      final data = resp.data;
      final rawUsers = data is Map ? data['users'] : null;
      if (rawUsers is! List) {
        throw 'استجابة قائمة المستخدمين غير مكتملة من السيرفر';
      }
      return rawUsers
          .whereType<Map>()
          .map((item) => User.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } on DioException catch (e) {
      throw _formatError(e);
    }
  }

  Future<User> adminCreateUser({
    required String username,
    required String password,
    required String email,
    required String role,
    required String fullName,
    String? phone,
    Subscription? subscription,
  }) async {
    try {
      final resp = await _dio.post(
        '/admin/users/',
        data: {
          'username': username,
          'password': password,
          'email': email,
          'role': role,
          'full_name': fullName,
          'phone': phone,
          if (subscription != null) 'subscription': subscription.toJson(),
        },
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return _managedUserFromResponse(resp.data);
    } on DioException catch (e) {
      throw _formatError(e);
    }
  }

  Future<User> adminUpdateUser(User user, {String? newPassword}) async {
    try {
      final data = user.toJson();
      if (newPassword != null) data['new_password'] = newPassword;
      final resp = await _dio.put(
        '/admin/users/${user.id}/',
        data: data,
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return _managedUserFromResponse(resp.data);
    } on DioException catch (e) {
      throw _formatError(e);
    }
  }

  Future<void> adminDeactivateUser(int userId) async {
    try {
      await _dio.delete('/admin/users/$userId/');
    } on DioException catch (e) {
      throw _formatError(e);
    }
  }

  User _managedUserFromResponse(dynamic raw) {
    final data = raw is Map ? raw['user'] : null;
    if (data is! Map) {
      throw 'استجابة بيانات المستخدم غير مكتملة من السيرفر';
    }
    return User.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> clearTokens() async {
    _sessionEpoch.advance();
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userKey);
  }

  Future<bool> isAuthenticated() async {
    final cachedUser = await getCachedUser();
    if (cachedUser == null) {
      await clearTokens();
      return false;
    }
    final t = await _storage.read(key: _accessKey);
    if (t == null || t.isEmpty) return false;
    if (_isJwtExpired(t)) {
      final refreshed = await _refreshAccessToken();
      if (refreshed == null) {
        final stillHasAccess = await _storage.read(key: _accessKey);
        return stillHasAccess != null && stillHasAccess.isNotEmpty;
      }
    }
    return true;
  }

  Future<User?> getCachedUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null) return null;
    try {
      return User.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'ApiClient.getCachedUser');
      return null;
    }
  }

  // ============ HIERARCHY ============
  Future<List<HierarchyItem>> getHierarchy() async {
    final resp = await _withRetry(() => _dio.get('/hierarchy/'));
    final data = resp.data;
    if (data is List) {
      return data
          .map((e) => HierarchyItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (data is Map && data['hierarchy'] is List) {
      return (data['hierarchy'] as List)
          .whereType<Map>()
          .map((e) => HierarchyItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (data is Map && data['stages'] is List) {
      return (data['stages'] as List)
          .whereType<Map>()
          .map((e) => HierarchyItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  // ============ STUDENTS ============
  Future<ClassroomData> getStudents(
    int classId,
    String subject, {
    String? className,
    required int termId,
    required int weekNumber,
  }) async {
    final resp = await _withRetry(
      () => _dio.get(
        '/students/',
        queryParameters: {
          'class_id': classId,
          'subject': subject,
          'term_id': termId,
          'week_number': weekNumber,
        },
      ),
    );
    final raw = resp.data;
    if (raw is! Map) {
      throw 'استجابة غير متوقعة من السيرفر للطلاب';
    }
    final data = Map<String, dynamic>.from(raw);
    return ClassroomData.fromJson(data, className: className, subject: subject);
  }

  // ============ BULK SYNC ============
  Future<Map<String, dynamic>> syncGrades({
    required int termId,
    required int weekNumber,
    required String subject,
    required List<Map<String, dynamic>> grades,
    int? classId,
  }) async {
    final idempotencyKey = SyncRequestIdentity.forGrades(
      termId: termId,
      weekNumber: weekNumber,
      classId: classId,
      subject: subject,
      grades: grades,
    );
    final resp = await _withRetry(
      () => _dio.post(
        '/grades/sync/',
        data: {
          'term_id': termId,
          'week_number': weekNumber,
          'subject': subject,
          if (classId != null) 'class_id': classId,
          'grades': grades,
        },
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      ),
    );
    final r = resp.data;
    if (r is Map) return Map<String, dynamic>.from(r);
    return {};
  }

  // ============ VOICE TRANSCRIBE ============
  Future<String> transcribeAudio(String filePath) async {
    // Web platform لا تدعم dart:io File — أعد رسالة واضحة
    if (kIsWeb) {
      throw 'تحويل الصوت لنص عبر السيرفر غير متاح على متصفح الويب. '
          'استخدم التطبيق على الجهاز المحمول للحصول على هذه الميزة.';
    }

    if (!File(filePath).existsSync()) {
      throw 'الملف الصوتي غير موجود';
    }

    // يستخدم _withRetry مثل بقية الـ endpoints لإعادة المحاولة عند الأخطاء العابرة
    return _withRetry(() async {
      final form = FormData.fromMap({
        'audio': await MultipartFile.fromFile(
          filePath,
          filename: filePath.split('/').last,
        ),
      });
      final resp = await _dio.post(
        '/voice/transcribe/',
        data: form,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 90),
        ),
      );
      final d = resp.data;
      if (d is Map) {
        return (d['transcript'] ?? d['text'] ?? '').toString();
      }
      return '';
    });
  }

  // ============ ERROR HANDLING ============
  String _formatError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return 'انتهت مهلة الاتصال بالسيرفر';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'تعذر الاتصال بالسيرفر، تحقق من الإنترنت';
    }
    final code = e.response?.statusCode;
    final data = e.response?.data;
    if (code == 401 || code == 400) {
      String msg = 'بيانات الدخول غير صحيحة';
      if (data is Map) {
        msg =
            data['detail']?.toString() ??
            data['error']?.toString() ??
            data['message']?.toString() ??
            msg;
      }
      return msg;
    }
    if (data is Map) {
      return data['detail']?.toString() ??
          data['error']?.toString() ??
          'حدث خطأ في السيرفر (${code ?? '?'})';
    }
    return 'حدث خطأ غير متوقع';
  }

  bool _isNetworkException(DioException e) {
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown;
  }

  void _mergeSubscriptionFields(
    Map<String, dynamic> source,
    Map<String, dynamic> target,
  ) {
    if (target['subscription'] == null && source['subscription'] != null) {
      target['subscription'] = source['subscription'];
    }
    for (final key in [
      'subscription_plan',
      'billing_plan',
      'subscription_status',
      'subscription_expires_at',
      'current_period_end',
      'trial_ends_at',
      'lifetime',
      'is_lifetime',
    ]) {
      if (target[key] == null && source[key] != null) {
        target[key] = source[key];
      }
    }
  }

  bool _isJwtExpired(String token) {
    final expiry = _jwtExpiry(token);
    if (expiry == null) return false;
    return !DateTime.now().toUtc().isBefore(
      expiry.subtract(const Duration(seconds: 30)),
    );
  }

  DateTime? _jwtExpiry(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final data = jsonDecode(payload);
      if (data is! Map) return null;
      final exp = data['exp'];
      if (exp is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          exp.toInt() * 1000,
          isUtc: true,
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

/// Singleton accessor
final ApiClient apiClient = ApiClient();
