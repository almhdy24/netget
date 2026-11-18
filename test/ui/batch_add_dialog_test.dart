import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/data/sqlite_download_repository.dart';
import 'package:netget/models/data_budget.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/services/data_budget_service.dart';
import 'package:netget/services/download_manager.dart';
import 'package:netget/ui/dialogs/batch_add_dialog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late SqliteDownloadRepository repo;
  late DownloadManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_batch_test_');
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

  testWidgets('BatchAddDialog parses multiple URLs and adds them to queue', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const batchText = '''
https://example.com/file1.zip
https://example.com/song.mp3
invalid_text_line
https://example.com/doc.pdf
''';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: BatchAddDialog(manager: manager, initialText: batchText),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('إضافة دفعة روابط (Batch Add)'), findsOneWidget);
    // 3 valid URLs recognized out of 4 lines
    expect(find.textContaining('3 رابط'), findsOneWidget);

    // Select Wi-Fi only policy
    await tester.tap(find.text('واي-فاي فقط'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Toggle startNow to false (download later)
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Tap submit button
    final submitFinder = find.byType(FilledButton);
    expect(submitFinder, findsOneWidget);
    final submitButton = tester.widget<FilledButton>(submitFinder);
    expect(submitButton.onPressed, isNotNull);

    await tester.runAsync(() async {
      submitButton.onPressed!();
      for (int i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (manager.tasks.length == 3) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          break;
        }
      }
    });
    await tester.pump();

    // Verify all 3 downloads were added to the manager
    expect(manager.tasks.length, equals(3));
    expect(
      manager.tasks.map((t) => t.fileName).toSet(),
      containsAll(['file1.zip', 'song.mp3', 'doc.pdf']),
    );
    // Verify policy and status
    for (final task in manager.tasks) {
      expect(task.networkPolicy, equals(NetworkPolicy.wifiOnly));
      expect(task.status, equals(DownloadStatus.paused));
    }
  });
}
