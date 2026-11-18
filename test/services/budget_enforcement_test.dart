import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/data/sqlite_download_repository.dart';
import 'package:netget/models/app_settings.dart';
import 'package:netget/models/data_budget.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/services/data_budget_service.dart';
import 'package:netget/services/download_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Database db;
  late SqliteDownloadRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_budget_test_');
    final dbPath = '${tempDir.path}/test.db';
    repo = SqliteDownloadRepository(customDbPath: dbPath);
    db = await repo.database;
  });

  tearDown(() async {
    try {
      await db.close();
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('DownloadManager Budget Enforcement', () {
    test('pauses wifiOnly download when network is mobile', () async {
      String currentNet = 'mobile';
      final budgetService = DataBudgetService(
        dbResolver: () async => db,
        networkTypeResolver: () async => currentNet,
      );

      final manager = DownloadManager(
        repository: repo,
        budgetService: budgetService,
        downloadsDirResolver: () async => tempDir,
      );
      await manager.init();

      final task = await manager.addDownload(
        url: 'https://example.com/testfile.zip',
        startNow: true,
        networkPolicy: NetworkPolicy.wifiOnly,
      );

      // Give event loop time to process start
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final updated = manager.tasks.firstWhere((t) => t.id == task.id);
      expect(updated.status, equals(DownloadStatus.paused));
      expect(updated.pauseReason, equals('network'));

      manager.dispose();
    });

    test(
      'auto-resumes paused task when switching to Wi-Fi via evaluatePolicyAndWindows',
      () async {
        String currentNet = 'mobile';
        final budgetService = DataBudgetService(
          dbResolver: () async => db,
          networkTypeResolver: () async => currentNet,
        );

        final manager = DownloadManager(
          repository: repo,
          budgetService: budgetService,
          downloadsDirResolver: () async => tempDir,
        );
        await manager.init();

        final task = await manager.addDownload(
          url: 'https://example.com/video.mp4',
          startNow: false,
          networkPolicy: NetworkPolicy.wifiOnly,
        );

        // Pause with reason network
        await manager.pauseDownload(task.id, reason: 'network');
        expect(manager.tasks.first.status, equals(DownloadStatus.paused));
        expect(manager.tasks.first.pauseReason, equals('network'));

        // Switch to Wi-Fi and evaluate
        currentNet = 'wifi';
        await manager.evaluatePolicyAndWindows();

        expect(
          manager.tasks.first.status,
          anyOf(
            equals(DownloadStatus.queued),
            equals(DownloadStatus.downloading),
          ),
        );
        expect(manager.tasks.first.pauseReason, isNull);

        manager.dispose();
      },
    );

    test(
      'pauses download with budget reason when budget hard stop is hit on mobile',
      () async {
        final now = DateTime(2026, 5, 10, 12, 0);
        String currentNet = 'mobile';

        // Insert 5 GB usage into ledger for this cycle
        final cycleStart = DateTime(2026, 5, 1);
        await db.insert('usage_ledger', {
          'timestamp': cycleStart
              .add(const Duration(days: 2))
              .millisecondsSinceEpoch,
          'task_id': 'prior_task',
          'bytes': 5 * 1024 * 1024 * 1024,
          'network_type': 'mobile',
        });

        final budgetService = DataBudgetService(
          dbResolver: () async => db,
          networkTypeResolver: () async => currentNet,
        );

        const settings = AppSettings(
          monthlyBudgetBytes: 5 * 1024 * 1024 * 1024, // 5 GB cap
          budgetHardStop: true,
        );

        final manager = DownloadManager(
          repository: repo,
          budgetService: budgetService,
          settings: settings,
          downloadsDirResolver: () async => tempDir,
        );
        manager.clock = () => now;
        await manager.init();

        final task = await manager.addDownload(
          url: 'https://example.com/heavy.iso',
          startNow: true,
          networkPolicy: NetworkPolicy.anyNetwork,
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));

        final updated = manager.tasks.firstWhere((t) => t.id == task.id);
        expect(updated.status, equals(DownloadStatus.paused));
        expect(updated.pauseReason, equals('budget'));

        manager.dispose();
      },
    );

    test(
      'allows wifiOrFreeWindow download during night bundle hours on mobile',
      () async {
        // 03:00 (inside 02:00-06:00 free window)
        final nightTime = DateTime(2026, 5, 10, 3, 0);
        String currentNet = 'mobile';

        final budgetService = DataBudgetService(
          dbResolver: () async => db,
          networkTypeResolver: () async => currentNet,
        );

        const nightWindow = FreeWindow(
          label: 'Night Bundle',
          start: TimeOfDay(hour: 2, minute: 0),
          end: TimeOfDay(hour: 6, minute: 0),
        );

        final settings = const AppSettings(freeWindows: [nightWindow]);

        final manager = DownloadManager(
          repository: repo,
          budgetService: budgetService,
          settings: settings,
          downloadsDirResolver: () async => tempDir,
        );
        manager.clock = () => nightTime;
        await manager.init();

        final check = await budgetService.checkAllowed(
          policy: NetworkPolicy.wifiOrFreeWindow,
          settings: settings,
          isWifiOverride: false,
          now: nightTime,
        );
        expect(check.isAllowed, isTrue);

        manager.dispose();
      },
    );

    test(
      'records downloaded delta bytes in usage ledger on emitProgressTick',
      () async {
        final now = DateTime(2026, 5, 10, 10, 0);
        final budgetService = DataBudgetService(
          dbResolver: () async => db,
          networkTypeResolver: () async => 'mobile',
        );

        final manager = DownloadManager(
          repository: repo,
          budgetService: budgetService,
          downloadsDirResolver: () async => tempDir,
        );
        manager.clock = () => now;
        await manager.init();

        final task = await manager.addDownload(
          url: 'https://example.com/file.bin',
          startNow: false,
        );

        // Set status to downloading
        manager.updateTaskForTesting(
          task.copyWith(status: DownloadStatus.downloading),
        );

        manager.emitProgressTick(
          task.id,
          downloadedBytes: 1048576, // 1 MB
          speedBytesPerSec: 500000,
        );

        await Future<void>.delayed(const Duration(milliseconds: 100));

        final rows = await db.query(
          'usage_ledger',
          where: 'task_id = ?',
          whereArgs: [task.id],
        );
        expect(rows.isNotEmpty, isTrue);
        expect(rows.first['bytes'], equals(1048576));
        expect(rows.first['network_type'], equals('mobile'));

        manager.dispose();
      },
    );
  });
}
