import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/grading_provider.dart';
import 'providers/theme_provider.dart';
import 'services/app_initialization_service.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'utils/error_handler.dart';
import 'utils/error_recovery.dart';

Future<void> main() async {
  // تثبيت معالجات الأخطاء العالمية قبل أي كود آخر
  ErrorHandler.install();

  // استبدال شاشة الخطأ الحمراء بشاشة ودية
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return FriendlyErrorWidget(details: details);
  };

  ErrorHandler.runGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    if (kDebugMode) {
      debugPrint('[BOOTSTRAP] ========== APP STARTUP ==========');
      debugPrint('[BOOTSTRAP] Timestamp: ${DateTime.now()}');
    }

    // تعطيل جلب الخطوط أثناء التشغيل (الخطوط محلية)
    try {
      GoogleFonts.config.allowRuntimeFetching = false;
    } catch (e) {
      errorRecovery.recordError(
        'GoogleFonts configuration failed: $e',
        null,
        context: 'main_googleFonts',
      );
    }

    // إعداد واجهة النظام
    try {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[BOOTSTRAP] system UI config failed: $e');
    }

    // إجبار الاتجاه العمودي فقط
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } catch (e) {
      if (kDebugMode) debugPrint('[BOOTSTRAP] orientation config failed: $e');
    }

    // تهيئة الخدمات
    final initSuccess = await appInitialization.initializeApp();
    if (kDebugMode) {
      debugPrint('[BOOTSTRAP] init ${initSuccess ? "OK" : "with errors"}');
    }

    runApp(const VoiceGraderApp());
  });
}

class VoiceGraderApp extends StatelessWidget {
  const VoiceGraderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            try {
              return AuthProvider();
            } catch (e, s) {
              errorRecovery.recordError(
                'AuthProvider creation failed: $e',
                s,
                context: 'AuthProvider_create',
              );
              rethrow;
            }
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            try {
              return GradingProvider();
            } catch (e, s) {
              errorRecovery.recordError(
                'GradingProvider creation failed: $e',
                s,
                context: 'GradingProvider_create',
              );
              rethrow;
            }
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            try {
              return ThemeProvider();
            } catch (e, s) {
              errorRecovery.recordError(
                'ThemeProvider creation failed: $e',
                s,
                context: 'ThemeProvider_create',
              );
              rethrow;
            }
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'StudyGrades 2026',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          locale: const Locale('ar', 'EG'),
          supportedLocales: const [
            Locale('ar', 'EG'),
            Locale('ar', ''),
            Locale('en', 'US'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            // قيود TextScaler للاحترافية
            final mq = MediaQuery.of(context);
            final clampedScale = mq.textScaler.scale(1.0).clamp(0.85, 1.15);
            return Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: mq.copyWith(
                  textScaler: TextScaler.linear(clampedScale),
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
