import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'data/download_repository.dart';
import 'data/settings_repository.dart';
import 'l10n/generated/app_localizations.dart';
import 'models/app_settings.dart';
import 'services/analytics_service.dart';
import 'services/download_manager.dart';
import 'ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Explicitly enable Edge-to-Edge system UI mode across Android versions
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Set Android system navigation/status bar styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  // Hook global Flutter error capture
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    AnalyticsService.recordError(
      details.exception,
      details.stack,
      context: 'FlutterError',
      fatal: false,
    );
    if (originalOnError != null) {
      originalOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  // Hook asynchronous platform error capture
  PlatformDispatcher.instance.onError = (error, stack) {
    AnalyticsService.recordError(
      error,
      stack,
      context: 'PlatformDispatcher',
      fatal: true,
    );
    return false;
  };

  final settingsRepository = SettingsRepository();
  final initialSettings = await settingsRepository.loadSettings();

  // Initialize AlmHdyAnalytics safely before runApp
  await AnalyticsService.initialize(
    projectKey: NetGetConstants.almhdyAnalyticsProjectKey,
    appVersion: NetGetConstants.appVersion,
    debug: kDebugMode,
  );

  // Sync persisted opt-out state
  await AnalyticsService.setEnabled(initialSettings.analyticsEnabled);

  // Record initial application launch
  AnalyticsService.trackAppOpen();

  final repository = JsonDownloadRepository();
  final manager = DownloadManager(repository: repository);
  await manager.init();

  runApp(
    NetGetApp(
      manager: manager,
      settingsRepository: settingsRepository,
      initialSettings: initialSettings,
    ),
  );
}

class NetGetApp extends StatefulWidget {
  final DownloadManager manager;
  final SettingsRepository? settingsRepository;
  final AppSettings initialSettings;

  const NetGetApp({
    super.key,
    required this.manager,
    this.settingsRepository,
    this.initialSettings = const AppSettings(),
  });

  @override
  State<NetGetApp> createState() => _NetGetAppState();
}

class _NetGetAppState extends State<NetGetApp> with WidgetsBindingObserver {
  late final ValueNotifier<ThemeMode> _themeModeNotifier;
  late final SettingsRepository _settingsRepository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settingsRepository = widget.settingsRepository ?? SettingsRepository();
    _themeModeNotifier = ValueNotifier<ThemeMode>(
      widget.initialSettings.themeMode,
    );
    _themeModeNotifier.addListener(_onThemeChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      AnalyticsService.trackAppBackground();
    } else if (state == AppLifecycleState.resumed) {
      AnalyticsService.trackAppOpen();
    }
  }

  void _onThemeChanged() {
    _settingsRepository.saveThemeMode(_themeModeNotifier.value);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeModeNotifier.removeListener(_onThemeChanged);
    _themeModeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = _themeModeNotifier.value;
    final platformBrightness =
        MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            platformBrightness == Brightness.dark);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    );

    final lang = widget.initialSettings.language;
    final locale = lang == 'ar'
        ? const Locale('ar')
        : (lang == 'en' ? const Locale('en') : null);

    return MaterialApp(
      title: '${NetGetConstants.appName} – ${NetGetConstants.appFullName}',
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      themeMode: themeMode,
      theme: NetGetTheme.lightTheme(),
      darkTheme: NetGetTheme.darkTheme(),
      home: HomeScreen(
        manager: widget.manager,
        themeModeNotifier: _themeModeNotifier,
        settingsRepository: _settingsRepository,
      ),
    );
  }
}
