import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_handler.dart';

/// مزود السمات - يدير الوضع الفاتح والداكن
class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'app_theme_mode';

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_themeKey);
      if (saved == 'dark') {
        _themeMode = ThemeMode.dark;
      } else if (saved == 'light') {
        _themeMode = ThemeMode.light;
      } else {
        _themeMode = ThemeMode.system;
      }
      notifyListeners();
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'ThemeProvider.loadTheme');
      _themeMode = ThemeMode.light;
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      String value;
      switch (mode) {
        case ThemeMode.dark:
          value = 'dark';
          break;
        case ThemeMode.light:
          value = 'light';
          break;
        case ThemeMode.system:
          value = 'system';
          break;
      }
      await prefs.setString(_themeKey, value);
    } catch (e, st) {
      ErrorHandler.logError(e, st, 'ThemeProvider.setTheme');
    }
  }

  Future<void> toggleTheme() async {
    await setTheme(isDarkMode ? ThemeMode.light : ThemeMode.dark);
  }
}
