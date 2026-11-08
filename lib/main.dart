import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'data/download_repository.dart';
import 'data/settings_repository.dart';
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

  final repository = JsonDownloadRepository();
  final manager = DownloadManager(repository: repository);
  await manager.init();

  final settingsRepository = SettingsRepository();
  final initialThemeMode = await settingsRepository.loadThemeMode();

  runApp(NetGetApp(
    manager: manager,
    settingsRepository: settingsRepository,
    initialThemeMode: initialThemeMode,
  ));
}

class NetGetApp extends StatefulWidget {
  final DownloadManager manager;
  final SettingsRepository? settingsRepository;
  final ThemeMode initialThemeMode;

  const NetGetApp({
    super.key,
    required this.manager,
    this.settingsRepository,
    this.initialThemeMode = ThemeMode.system,
  });

  @override
  State<NetGetApp> createState() => _NetGetAppState();
}

class _NetGetAppState extends State<NetGetApp> {
  late final ValueNotifier<ThemeMode> _themeModeNotifier;
  late final SettingsRepository _settingsRepository;

  @override
  void initState() {
    super.initState();
    _settingsRepository = widget.settingsRepository ?? SettingsRepository();
    _themeModeNotifier = ValueNotifier<ThemeMode>(widget.initialThemeMode);
    _themeModeNotifier.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    _settingsRepository.saveThemeMode(_themeModeNotifier.value);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _themeModeNotifier.removeListener(_onThemeChanged);
    _themeModeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = _themeModeNotifier.value;
    final platformBrightness =
        MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            platformBrightness == Brightness.dark);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    );

    return MaterialApp(
      title: '${NetGetConstants.appName} – ${NetGetConstants.appFullName}',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: NetGetTheme.lightTheme(),
      darkTheme: NetGetTheme.darkTheme(),
      home: HomeScreen(
        manager: widget.manager,
        themeModeNotifier: _themeModeNotifier,
      ),
    );
  }
}
