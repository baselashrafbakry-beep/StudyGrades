import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

    // Critical initializations — wrapped with timeouts so a single
    // hang can never prevent the app from booting on real devices.
    try {
      await StorageService.init()
          .timeout(const Duration(seconds: 4));
    } catch (e, s) {
      ErrorHandler.logError(e, s, 'StorageService.init');
    }
    try {
      await connectivityService.init()
          .timeout(const Duration(seconds: 3));
    } catch (e, s) {
      ErrorHandler.logError(e, s, 'ConnectivityService.init');
    }
    try {
      await AdminService.initDefaultDeveloper()
          .timeout(const Duration(seconds: 3));
    } catch (e, s) {
      ErrorHandler.logError(e, s, 'AdminService.initDefaultDeveloper');
    }

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    runApp(const VoiceGraderApp());
  });
}

class VoiceGraderApp extends StatelessWidget {
  const VoiceGraderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => GradingProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
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
