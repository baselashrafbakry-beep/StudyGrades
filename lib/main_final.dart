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
    print('[BOOTSTRAP] Platform: ${Theme.of(WidgetsBinding.instance.window as dynamic).platform}');

    // CRITICAL: Disable runtime HTTP fetching of Google Fonts.
    try {
      GoogleFonts.config.allowRuntimeFetching = false;
      print('[BOOTSTRAP] ✓ GoogleFonts configured (runtime fetching disabled)');
    } catch (e) {
      print('[BOOTSTRAP] ⚠️ Failed to configure GoogleFonts: $e');
      errorRecovery.recordError(
        'GoogleFonts configuration failed: $e',
        null,
        context: 'main_googleFonts',
      );
    }

    // System UI configuration
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
      print('[BOOTSTRAP] ⚠️ Failed to configure system UI: $e');
    }

    // Set preferred orientations
    try {
      print('[BOOTSTRAP] Setting preferred orientations...');
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      print('[BOOTSTRAP] ✓ Orientations configured');
    } catch (e) {
      print('[BOOTSTRAP] ⚠️ Failed to set orientations: $e');
    }

    // Initialize app services with comprehensive error handling
    print('[BOOTSTRAP] Starting app initialization...');
    final initSuccess = await appInitialization.initializeApp();
    
    if (initSuccess) {
      print('[BOOTSTRAP] ✓ App initialization successful');
    } else {
      print('[BOOTSTRAP] ⚠️ App initialization completed with errors');
    }

    print('[BOOTSTRAP] Initialization Log:');
    for (final log in appInitialization.initializationLog) {
      print('[BOOTSTRAP]   $log');
    }

    print('[BOOTSTRAP] Launching app...');
    print('[BOOTSTRAP] ========== APP RUNNING ==========');
    runApp(const VoiceGraderApp());
  });
}

class VoiceGraderApp extends StatefulWidget {
  const VoiceGraderApp({super.key});

  @override
  State<VoiceGraderApp> createState() => _VoiceGraderAppState();
}

class _VoiceGraderAppState extends State<VoiceGraderApp> {
  late Future<void> _providerInitFuture;

  @override
  void initState() {
    super.initState();
    _providerInitFuture = _initializeProviders();
  }

  Future<void> _initializeProviders() async {
    print('[PROVIDERS] Initializing providers...');
    try {
      // Providers will be created lazily by MultiProvider
      print('[PROVIDERS] ✓ Providers ready');
    } catch (e, s) {
      print('[PROVIDERS] ✗ Provider initialization failed: $e');
      errorRecovery.recordError(
        'Provider initialization failed: $e',
        s,
        context: '_initializeProviders',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _providerInitFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return MaterialApp(
            home: Scaffold(
              body: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          );
        }

        return MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) {
                try {
                  print('[PROVIDER] Creating AuthProvider...');
                  return AuthProvider();
                } catch (e, s) {
                  print('[PROVIDER] ✗ Failed to create AuthProvider: $e');
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
                  print('[PROVIDER] Creating GradingProvider...');
                  return GradingProvider();
                } catch (e, s) {
                  print('[PROVIDER] ✗ Failed to create GradingProvider: $e');
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
                  print('[PROVIDER] Creating ThemeProvider...');
                  return ThemeProvider();
                } catch (e, s) {
                  print('[PROVIDER] ✗ Failed to create ThemeProvider: $e');
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
      },
    );
  }
}
