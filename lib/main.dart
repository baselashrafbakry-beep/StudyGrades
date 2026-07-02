import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/grading_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'services/admin_service.dart';
import 'services/connectivity_service.dart';
import 'theme/app_theme.dart';
import 'utils/error_handler.dart';
// import 'utils/error_recovery.dart'  // متاح للاستخدام عند الحاجة;

/// ═══════════════════════════════════════════════════
/// Study Grades Voice - نظام رصد الدرجات الصوتي
/// المطور: م. باسل أشرف
/// الإصدار: 2.0.0
/// ═══════════════════════════════════════════════════
void main() async {
  // 1. تثبيت معالج الأخطاء العالمي أولاً
  ErrorHandler.install();

  // 2. تشغيل التطبيق داخل Zone آمنة لالتقاط أي استثناء غير معالج
  ErrorHandler.runGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 3. تهيئة الاتجاه - portrait فقط للتطبيق المحمول
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // 4. تهيئة ألوان شريط الحالة
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0D47A1),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // 5. تعطيل تحميل الخطوط من الإنترنت (نستخدم خطوط محلية)
    GoogleFonts.config.allowRuntimeFetching = false;

    // 6. تهيئة Hive للتخزين المحلي
    try {
      await Hive.initFlutter();
    } catch (e, s) {
      ErrorHandler.logError(e, s, 'Hive.initFlutter');
    }

    // 7. تهيئة StorageService مع timeout آمن
    try {
      await _initStorageSafe();
    } catch (e, s) {
      ErrorHandler.logError(e, s, 'StorageService.init');
      // التطبيق يكمل حتى لو فشل التخزين - يعمل بوضع مؤقت
    }

    // 8. تهيئة خدمة الاتصال
    try {
      await connectivityService
          .init()
          .timeout(const Duration(seconds: 3));
    } catch (e, s) {
      ErrorHandler.logError(e, s, 'ConnectivityService.init');
    }

    // 9. تهيئة حساب المطور الافتراضي (محلياً)
    try {
      await AdminService.initDefaultDeveloper()
          .timeout(const Duration(seconds: 3));
    } catch (e, s) {
      ErrorHandler.logError(e, s, 'AdminService.initDefaultDeveloper');
    }

    // 10. تخصيص widget الخطأ المرئي
    ErrorWidget.builder = (FlutterErrorDetails details) {
      ErrorHandler.logError(
        details.exception,
        details.stack,
        'ErrorWidget',
      );
      return FriendlyErrorWidget(details: details);
    };

    if (kDebugMode) {
      debugPrint('[MAIN] ✅ All services initialized — launching app');
    }

    runApp(const StudyGradesApp());
  });
}

/// تهيئة التخزين بأمان مع إعادة المحاولة
Future<void> _initStorageSafe() async {
  const maxRetries = 2;
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      await _initStorage()
          .timeout(const Duration(seconds: 5));
      return;
    } catch (e) {
      if (attempt == maxRetries) rethrow;
      await Future.delayed(Duration(milliseconds: 300 * attempt));
    }
  }
}

Future<void> _initStorage() async {
  // فتح صناديق Hive الأساسية
  const boxes = [
    'pending_grades_box',
    'settings_box',
    'classroom_cache_box',
    'admin_users_box',
    'admin_settings_box',
    'admin_activity_box',
  ];
  for (final boxName in boxes) {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox(boxName);
    }
  }
}

/// الـ Root Widget الرئيسي للتطبيق
class StudyGradesApp extends StatelessWidget {
  const StudyGradesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          lazy: false,
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(),
          lazy: false,
        ),
        ChangeNotifierProvider<GradingProvider>(
          create: (_) => GradingProvider(),
          lazy: true,
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            // ─── بيانات التطبيق ───
            title: 'Study Grades Voice',
            debugShowCheckedModeBanner: false,

            // ─── السمات ───
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,

            // ─── الاتجاه RTL للعربية ───
            locale: const Locale('ar'),
            builder: (context, child) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              );
            },

            // ─── الشاشة الرئيسية ───
            home: const SplashScreen(),

            // ─── معالج الأخطاء المرئية ───
            // يُظهر شاشة خطأ احترافية بدلاً من الشاشة الحمراء
          );
        },
      ),
    );
  }
}
