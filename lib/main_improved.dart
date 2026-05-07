import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/grading_provider.dart';
import 'providers/theme_provider.dart';
import 'services/admin_service.dart';
import 'services/storage_service.dart';
import 'services/connectivity_service.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'utils/error_handler.dart';

Future<void> main() async {
  // Install global error handlers BEFORE any framework code runs.
  ErrorHandler.install();

  // Replace the default red-screen-of-death with a friendly fallback.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return FriendlyErrorWidget(details: details);
  };

  ErrorHandler.runGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    print('[BOOTSTRAP] ========== APP STARTUP ==========');
    print('[BOOTSTRAP] Timestamp: ${DateTime.now()}');

    // CRITICAL: Disable runtime HTTP fetching of Google Fonts.
    try {
      GoogleFonts.config.allowRuntimeFetching = false;
      print('[BOOTSTRAP] GoogleFonts configured (runtime fetching disabled)');
    } catch (e) {
      print('[ERROR] Failed to configure GoogleFonts: $e');
    }

    // Critical initializations — wrapped with timeouts
    print('[BOOTSTRAP] Starting critical initializations...');
    
    try {
      print('[BOOTSTRAP] Initializing StorageService...');
      await StorageService.init()
          .timeout(const Duration(seconds: 4));
      print('[BOOTSTRAP] ✓ StorageService initialized successfully');
    } catch (e, s) {
      print('[ERROR] StorageService.init failed: $e');
      print('[STACK] $s');
      ErrorHandler.logError(e, s, 'StorageService.init');
    }
    
    try {
      print('[BOOTSTRAP] Initializing ConnectivityService...');
      await connectivityService.init()
          .timeout(const Duration(seconds: 3));
      print('[BOOTSTRAP] ✓ ConnectivityService initialized successfully');
    } catch (e, s) {
      print('[ERROR] ConnectivityService.init failed: $e');
      print('[STACK] $s');
      ErrorHandler.logError(e, s, 'ConnectivityService.init');
    }
    
    try {
      print('[BOOTSTRAP] Initializing AdminService...');
      await AdminService.initDefaultDeveloper()
          .timeout(const Duration(seconds: 3));
      print('[BOOTSTRAP] ✓ AdminService initialized successfully');
    } catch (e, s) {
      print('[ERROR] AdminService.initDefaultDeveloper failed: $e');
      print('[STACK] $s');
      ErrorHandler.logError(e, s, 'AdminService.initDefaultDeveloper');
    }
    
    print('[BOOTSTRAP] Critical initializations completed');

    try {
      print('[BOOTSTRAP] Configuring system UI...');
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      );
      print('[BOOTSTRAP] ✓ System UI configured');
    } catch (e) {
      print('[ERROR] Failed to configure system UI: $e');
    }

    try {
      print('[BOOTSTRAP] Setting preferred orientations...');
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      print('[BOOTSTRAP] ✓ Orientations configured');
    } catch (e) {
      print('[ERROR] Failed to set orientations: $e');
    }

    print('[BOOTSTRAP] Launching app...');
    print('[BOOTSTRAP] ========== APP RUNNING ==========');
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
              print('[PROVIDER] Creating AuthProvider...');
              return AuthProvider();
            } catch (e, s) {
              print('[ERROR] Failed to create AuthProvider: $e');
              print('[STACK] $s');
              rethrow;
            }
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            try {
              print('[PROVIDER] Creating GradingProvider...');
              return GradingProvider();
            } catch (e, s) {
              print('[ERROR] Failed to create GradingProvider: $e');
              print('[STACK] $s');
              rethrow;
            }
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            try {
              print('[PROVIDER] Creating ThemeProvider...');
              return ThemeProvider();
            } catch (e, s) {
              print('[ERROR] Failed to create ThemeProvider: $e');
              print('[STACK] $s');
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
            return Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(
                    MediaQuery.of(context)
                        .textScaler
                        .scale(1.0)
                        .clamp(0.85, 1.15),
                  ),
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
