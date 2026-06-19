import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import '../models/hierarchy_model.dart';
import '../models/student_model.dart';
import '../utils/error_handler.dart';

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

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late final Dio _dio;
  Future<String?>? _refreshFuture;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
        headers: {'Accept': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: _accessKey);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (e, handler) async {
          // 401 -> try refresh once and replay the original request
          if (e.response?.statusCode == 401 &&
              e.requestOptions.path != '/token/refresh/' &&
              e.requestOptions.path != '/login/' &&
              e.requestOptions.extra['_retried'] != true) {
            try {
              final newToken = await _refreshAccessToken();
              if (newToken != null) {
                final opts = e.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newToken';
                opts.extra['_retried'] = true;
                final cloneResp = await _dio.fetch(opts);
                return handler.resolve(cloneResp);
              }
            } catch (e, st) {
              ErrorHandler.logError(e, st, 'ApiClient.refreshRetry');
              await clearTokens();
            }
          }
          handler.next(e);
        },
      ),
    );
  }

  Future<String?> _refreshAccessToken() async {
    if (_refreshFuture != null) return _refreshFuture;
    _refreshFuture = (() async {
      try {
        final refresh = await _storage.read(key: _refreshKey);
        if (refresh == null || refresh.isEmpty) return null;
        final resp = await Dio().post(
          '$baseUrl/token/refresh/',
          data: {'refresh': refresh},
          options: Options(headers: {'Content-Type': 'application/json'}),
        );
        final newAccess = resp.data['access']?.toString();
        if (newAccess != null) {
          await _storage.write(key: _accessKey, value: newAccess);
          return newAccess;
        }
      } catch (e, st) {
        ErrorHandler.logError(e, st, 'ApiClient.refreshAccessToken');
        return null;
      } finally {
        _refreshFuture = null;
      }
      return null;
    })();
    return _refreshFuture;
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
        final transient = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.connectionError ||
            (e.response?.statusCode != null &&
                e.response!.statusCode! >= 500);
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
    for (final ep in endpoints) {
      try {
        resp = await _dio.post(
          ep,
          data: {'username': username, 'password': password},
          options: Options(headers: {'Content-Type': 'application/json'}),
        );
        break;
      } on DioException catch (e) {
        lastErr = e;
        if (e.response?.statusCode == 401 || e.response?.statusCode == 400) {
          throw _formatError(e);
        }
        // 404 / 405 -> try next endpoint
      }
    }
    if (resp == null) {
      throw _formatError(lastErr!);
    }

    final data = Map<String, dynamic>.from(resp.data);
    final access = data['access']?.toString();
    final refresh = data['refresh']?.toString();
    if (access == null || refresh == null) {
      throw 'استجابة غير متوقعة من السيرفر';
    }
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);

    User user;
    if (data['user'] is Map) {
      user = User.fromJson(Map<String, dynamic>.from(data['user']));
    } else {
      user = User(id: 0, username: username, email: '', role: 'teacher');
    }
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    return {'user': user, 'access': access, 'refresh': refresh};
  }

  Future<void> logout() async {
    try {
      await _dio.post('/logout/');
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'ApiClient.logout');
    }
    await clearTokens();
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userKey);
  }

  Future<bool> isAuthenticated() async {
    final t = await _storage.read(key: _accessKey);
    return t != null && t.isNotEmpty;
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
  }) async {
    final resp = await _withRetry(() => _dio.get(
          '/students/',
          queryParameters: {'class_id': classId, 'subject': subject},
        ));
    final raw = resp.data;
    if (raw is! Map) {
      throw 'استجابة غير متوقعة من السيرفر للطلاب';
    }
    final data = Map<String, dynamic>.from(raw);
    return ClassroomData.fromJson(
      data,
      className: className,
      subject: subject,
    );
  }

  // ============ BULK SYNC ============
  Future<Map<String, dynamic>> syncGrades({
    required int termId,
    required int weekNumber,
    required String subject,
    required List<Map<String, dynamic>> grades,
    int? classId,
  }) async {
    final resp = await _withRetry(() => _dio.post(
          '/grades/sync/',
          data: {
            'term_id': termId,
            'week_number': weekNumber,
            'subject': subject,
            if (classId != null) 'class_id': classId,
            'grades': grades,
          },
        ));
    final r = resp.data;
    if (r is Map) return Map<String, dynamic>.from(r);
    return {};
  }

  // ============ VOICE TRANSCRIBE ============
  Future<String> transcribeAudio(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw 'الملف الصوتي غير موجود';
    }
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
        msg = data['detail']?.toString() ??
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
}

/// Singleton accessor
final ApiClient apiClient = ApiClient();
