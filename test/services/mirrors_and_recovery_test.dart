import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/data/sqlite_download_repository.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/services/data_budget_service.dart';
import 'package:netget/services/download_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../support/test_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late SqliteDownloadRepository repo;
  late DataBudgetService budgetService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_mirrors_test_');
    final dbPath = '${tempDir.path}/test.db';
    repo = SqliteDownloadRepository(customDbPath: dbPath);
    final db = await repo.database;
    budgetService = DataBudgetService(
      dbResolver: () async => db,
      networkTypeResolver: () async => 'wifi',
    );
  });

  tearDown(() async {
    try {
      final db = await repo.database;
      if (db.isOpen) {
        await db.close();
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Mirrors and Link Recovery (§5.2)', () {
    test('addMirror and removeMirror correctly modify task mirrors', () async {
      final manager = DownloadManager(
        repository: repo,
        budgetService: budgetService,
        downloadsDirResolver: () async => tempDir,
      );
      await manager.init();

      final task = await manager.addDownload(
        url: 'https://example.com/file.zip',
        startNow: false,
        mirrors: ['https://mirror1.com/file.zip'],
      );

      expect(task.mirrors, equals(['https://mirror1.com/file.zip']));

      await manager.addMirror(task.id, 'https://mirror2.com/file.zip');
      var updated = manager.tasks.firstWhere((t) => t.id == task.id);
      expect(
        updated.mirrors,
        containsAll([
          'https://mirror1.com/file.zip',
          'https://mirror2.com/file.zip',
        ]),
      );

      // Duplicate addition should be ignored
      await manager.addMirror(task.id, 'https://mirror1.com/file.zip');
      updated = manager.tasks.firstWhere((t) => t.id == task.id);
      expect(updated.mirrors.length, equals(2));

      // Removing mirror
      await manager.removeMirror(task.id, 'https://mirror1.com/file.zip');
      updated = manager.tasks.firstWhere((t) => t.id == task.id);
      expect(updated.mirrors, equals(['https://mirror2.com/file.zip']));

      manager.dispose();
    });

    test(
      'pauses with html_instead_of_file when server returns HTML for binary file',
      () async {
        final server = NetGetTestServer();
        await server.start();

        final manager = DownloadManager(
          repository: repo,
          budgetService: budgetService,
          downloadsDirResolver: () async => tempDir,
        );
        await manager.init();

        try {
          // Add binary download (.zip) pointing to HTML endpoint
          final task = await manager.addDownload(
            url: 'http://127.0.0.1:${server.actualPort}/html_page',
            customFileName: 'archive.zip',
            startNow: true,
            connectionCount: 1,
          );

          // Wait for download attempt to encounter HTML response
          await Future<void>.delayed(const Duration(milliseconds: 300));

          final updated = manager.tasks.firstWhere((t) => t.id == task.id);
          expect(updated.status, equals(DownloadStatus.paused));
          expect(updated.pauseReason, equals('html_instead_of_file'));
          expect(
            updated.errorMessage,
            contains('ملف HTML بدلاً من الملف الأصلي'),
          );

          // Verify the file was not written with HTML content
          final file = File(updated.savePath);
          if (await file.exists()) {
            final content = await file.readAsString();
            expect(content.contains('Captcha Challenge'), isFalse);
          }
        } finally {
          manager.dispose();
          await server.stop();
        }
      },
    );

    test(
      'automatically fails over to working mirror when primary URL returns 403',
      () async {
        // Server 1 (primary): fails with 403 Forbidden
        final serverPrimary = NetGetTestServer();
        serverPrimary.statusInjectionByRequest[1] = HttpStatus.forbidden;
        serverPrimary.statusInjectionByRequest[2] = HttpStatus.forbidden;
        await serverPrimary.start();

        // Server 2 (mirror): works and has identical data
        final serverMirror = NetGetTestServer(
          customData: serverPrimary.data,
          dataSize: serverPrimary.data.length,
        );
        await serverMirror.start();

        final manager = DownloadManager(
          repository: repo,
          budgetService: budgetService,
          downloadsDirResolver: () async => tempDir,
        );
        await manager.init();

        try {
          final primaryUrl =
              'http://127.0.0.1:${serverPrimary.actualPort}/download';
          final mirrorUrl =
              'http://127.0.0.1:${serverMirror.actualPort}/download';

          final task = await manager.addDownload(
            url: primaryUrl,
            customFileName: 'payload.bin',
            startNow: true,
            mirrors: [mirrorUrl],
            connectionCount: 1,
          );

          // Wait for primary to fail with 403 and failover to mirror
          for (int i = 0; i < 20; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            final current = manager.tasks.firstWhere((t) => t.id == task.id);
            if (current.status == DownloadStatus.completed) {
              break;
            }
          }

          final updated = manager.tasks.firstWhere((t) => t.id == task.id);
          // Verify it switched URL to the working mirror
          expect(updated.url, equals(mirrorUrl));
          expect(updated.status, equals(DownloadStatus.completed));
          expect(updated.downloadedBytes, equals(serverMirror.data.length));
        } finally {
          manager.dispose();
          await serverPrimary.stop();
          await serverMirror.stop();
        }
      },
    );
  });
}
