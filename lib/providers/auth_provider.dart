import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/admin_service.dart';
import '../services/api_client.dart';
import '../utils/error_handler.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  User? _user;
  AuthStatus _status = AuthStatus.unknown;
  bool _isLoading = false;
  String? _error;
  bool _isLocalAuth = false; // هل تم الدخول محلياً (offline) أم عبر السيرفر

  User? get user => _user;
  AuthStatus get status => _status;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLocalAuth => _isLocalAuth;

  Future<void> restoreSession() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final isAuth = await apiClient.isAuthenticated();
      if (isAuth) {
        _user = await apiClient.getCachedUser();
        _status = _user == null
            ? AuthStatus.unauthenticated
            : AuthStatus.authenticated;
        _isLocalAuth = false;
      } else {
        _user = null;
        _status = AuthStatus.unauthenticated;
        _isLocalAuth = false;
      }
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'AuthProvider.restoreSession');
      _user = null;
      _status = AuthStatus.unauthenticated;
      _isLocalAuth = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// تسجيل الدخول - السيرفر أولاً، ولا يسمح بالاعتماد المحلي إلا عند تفعيله صراحة.
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      // المحاولة 1: تسجيل الدخول عبر السيرفر
      try {
        final result = await apiClient.login(username, password);
        _user = result['user'] as User;
        _status = AuthStatus.authenticated;
        _isLocalAuth = false;
        await AdminService.logActivity(
          'تسجيل دخول',
          'دخول عبر السيرفر: ${_user!.username}',
        );
        return true;
      } catch (serverError) {
        if (AdminService.localAuthEnabled &&
            _looksLikeNetworkOutage(serverError)) {
          final localUser = await AdminService.verifyCredentials(
            username,
            password,
          );
          if (localUser != null) {
            await apiClient.clearTokens();
            _user = localUser;
            _status = AuthStatus.authenticated;
            _isLocalAuth = true;
            await AdminService.logActivity(
              'تسجيل دخول',
              'دخول محلي: ${_user!.username} (${UserRole.label(_user!.role)})',
            );
            return true;
          }
        }
        // إذا فشل الاثنان، استخدم رسالة السيرفر
        _error = serverError.toString();
        _status = AuthStatus.unauthenticated;
        return false;
      }
    } catch (e) {
      _error = e.toString();
      _status = AuthStatus.unauthenticated;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      if (!_isLocalAuth) {
        await apiClient.logout();
      }
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'AuthProvider.logout');
    } finally {
      await apiClient.clearTokens();
    }
    if (_user != null) {
      await AdminService.logActivity('تسجيل خروج', 'خروج: ${_user!.username}');
    }
    _user = null;
    _status = AuthStatus.unauthenticated;
    _isLocalAuth = false;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_isLocalAuth) {
      throw Exception('تغيير كلمة المرور يتطلب تسجيل الدخول عبر الإنترنت');
    }
    _isLoading = true;
    _error = null;
    notifyListeners();
    final username = _user?.username;
    try {
      await apiClient.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      _user = null;
      _status = AuthStatus.unauthenticated;
      _isLocalAuth = false;
      if (username != null) {
        try {
          await AdminService.logActivity(
            'تغيير كلمة المرور',
            'تم تغيير كلمة مرور الحساب: $username',
          );
        } catch (e, st) {
          ErrorHandler.logError(e, st, 'AuthProvider.passwordChangeLog');
        }
      }
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshCurrentUser() async {
    if (_isLocalAuth) {
      throw Exception('تحديث الاشتراك يتطلب تسجيل الدخول عبر الإنترنت');
    }
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _user = await apiClient.getCurrentUser();
      _status = AuthStatus.authenticated;
      _isLocalAuth = false;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  bool _looksLikeNetworkOutage(Object error) {
    if (error is NetworkAuthException) return true;
    final message = error.toString().toLowerCase();
    return message.contains('connection') ||
        message.contains('network') ||
        message.contains('timeout') ||
        message.contains('socket') ||
        message.contains('offline');
  }
}
