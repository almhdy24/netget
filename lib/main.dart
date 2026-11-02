import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'data/download_repository.dart';
import 'services/download_manager.dart';
import 'ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set Android system navigation/status bar styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  final repository = JsonDownloadRepository();
  final manager = DownloadManager(repository: repository);
  await manager.init();

  runApp(NetGetApp(manager: manager));
}

class NetGetApp extends StatefulWidget {
  final DownloadManager manager;

  const NetGetApp({super.key, required this.manager});

  @override
  State<NetGetApp> createState() => _NetGetAppState();
}

class _NetGetAppState extends State<NetGetApp> {
  final ValueNotifier<ThemeMode> _themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  @override
  void dispose() {
    _themeModeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: '${NetGetConstants.appName} – ${NetGetConstants.appSubtitle}',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: NetGetTheme.lightTheme(),
          darkTheme: NetGetTheme.darkTheme(),
          home: HomeScreen(
            manager: widget.manager,
            themeModeNotifier: _themeModeNotifier,
          ),
        );
      },
    );
  }
}
