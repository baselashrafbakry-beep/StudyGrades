import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/admin_service.dart';
import '../services/api_client.dart';

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
    notifyListeners();
    try {
      final isAuth = await apiClient.isAuthenticated();
      if (isAuth) {
        _user = await apiClient.getCachedUser();
        _status = AuthStatus.authenticated;
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// تسجيل الدخول - يحاول السيرفر أولاً ثم يقع لقاعدة البيانات المحلية
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
        // المحاولة 2: تسجيل الدخول محلياً (للمطور والمدير)
        final localUser =
            await AdminService.verifyCredentials(username, password);
        if (localUser != null) {
          _user = localUser;
          _status = AuthStatus.authenticated;
          _isLocalAuth = true;
          await AdminService.logActivity(
            'تسجيل دخول',
            'دخول محلي: ${_user!.username} (${UserRole.label(_user!.role)})',
          );
          return true;
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
    notifyListeners();
    try {
      if (!_isLocalAuth) {
        await apiClient.logout();
      }
    } catch (_) {}
    if (_user != null) {
      await AdminService.logActivity(
        'تسجيل خروج',
        'خروج: ${_user!.username}',
      );
    }
    _user = null;
    _status = AuthStatus.unauthenticated;
    _isLocalAuth = false;
    _isLoading = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
