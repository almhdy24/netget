import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/data/settings_repository.dart';
import 'package:netget/data/sqlite_download_repository.dart';
import 'package:netget/models/app_settings.dart';
import 'package:netget/models/data_budget.dart';
import 'package:netget/services/data_budget_service.dart';
import 'package:netget/services/download_manager.dart';
import 'package:netget/ui/settings/budget_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late SqliteDownloadRepository repo;
  late SettingsRepository settingsRepo;
  late DownloadManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'netget_budget_screen_test_',
    );
    final dbPath = '${tempDir.path}/test.db';
    repo = SqliteDownloadRepository(customDbPath: dbPath);
    final db = await repo.database;
    final settingsFile = File('${tempDir.path}/settings.json');
    settingsRepo = SettingsRepository(file: settingsFile);

    const initialSettings = AppSettings(
      monthlyBudgetBytes: 10 * 1024 * 1024 * 1024, // 10 GB
      budgetResetDay: 15,
      budgetHardStop: true,
      freeWindows: [
        FreeWindow(
          label: 'MTN Night Bundle',
          start: TimeOfDay(hour: 2, minute: 0),
          end: TimeOfDay(hour: 6, minute: 0),
        ),
      ],
    );
    await settingsRepo.saveSettings(initialSettings);

    final budgetService = DataBudgetService(
      dbResolver: () async => db,
      networkTypeResolver: () async => 'wifi',
    );

    manager = DownloadManager(
      repository: repo,
      budgetService: budgetService,
      settings: initialSettings,
      downloadsDirResolver: () async => tempDir,
    );
    await manager.init();
  });

  tearDown(() async {
    manager.dispose();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets(
    'DataBudgetScreen displays budget overview, settings and free windows',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: DataBudgetScreen(
            settingsRepository: settingsRepo,
            manager: manager,
          ),
        ),
      );

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();

      // Verify Title and Cards
      expect(find.text('Data Budget & Free Windows'), findsOneWidget);
      expect(find.text('Current Billing Cycle'), findsOneWidget);
      expect(find.text('Monthly Data Budget Settings'), findsOneWidget);
      expect(find.text('Free Windows (Night Bundles)'), findsOneWidget);
      expect(find.text('MTN Night Bundle'), findsOneWidget);

      // Verify Hard Stop Switch is present and active
      expect(
        find.text('Hard stop on mobile data when budget reached'),
        findsOneWidget,
      );

      // Verify Default Policy Options
      expect(find.text('Any Network (Wi-Fi or Mobile Data)'), findsOneWidget);
      expect(find.text('Wi-Fi Only (Pause on mobile data)'), findsOneWidget);
    },
  );
}
