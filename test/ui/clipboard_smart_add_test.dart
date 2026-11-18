import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/data/sqlite_download_repository.dart';
import 'package:netget/services/data_budget_service.dart';
import 'package:netget/services/download_manager.dart';
import 'package:netget/ui/home_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late SqliteDownloadRepository repo;
  late DownloadManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_clip_test_');
    final dbPath = '${tempDir.path}/test.db';
    repo = SqliteDownloadRepository(customDbPath: dbPath);
    final db = await repo.database;
    final budgetService = DataBudgetService(
      dbResolver: () async => db,
      networkTypeResolver: () async => 'wifi',
    );
    manager = DownloadManager(
      repository: repo,
      budgetService: budgetService,
      downloadsDirResolver: () async => tempDir,
    );
    await manager.init();
  });

  tearDown(() async {
    manager.dispose();
    try {
      final db = await repo.database;
      if (db.isOpen) await db.close();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets(
    'HomeScreen detects clipboard download URL on resume and shows snackbar',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? mockClipboardText = 'https://example.com/test_video.mp4';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            if (call.method == 'Clipboard.setData') {
              mockClipboardText = (call.arguments as Map)['text'] as String?;
              return null;
            }
            if (call.method == 'Clipboard.getData') {
              return {'text': mockClipboardText};
            }
            return null;
          });

      final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: HomeScreen(
              manager: manager,
              themeModeNotifier: themeNotifier,
            ),
          ),
        ),
      );

      // Pump post-frame callback
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('رابط في الحافظة'), findsOneWidget);
      expect(find.text('تحميل'), findsOneWidget);

      // Verify that triggering resume with same clipboard text does not duplicate or nag
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Still only one snackbar action
      expect(find.text('تحميل'), findsOneWidget);

      // Advance time to let SnackBar timer finish cleanly
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
