import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/segment_planner.dart';
import 'package:netget/data/sqlite_download_repository.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sqlite_repo_test_');
    dbPath = p.join(tempDir.path, 'test_tasks.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'SqliteDownloadRepository saves, loads, updates, and deletes tasks with segments',
    () async {
      final repo = SqliteDownloadRepository(customDbPath: dbPath);

      final task = DownloadTask(
        id: 'task_1',
        url: 'https://example.com/file.iso',
        fileName: 'file.iso',
        savePath: '/downloads/file.iso',
        totalBytes: 2000,
        downloadedBytes: 500,
        status: DownloadStatus.downloading,
        connectionCount: 2,
        etag: '"abc123etag"',
        lastModified: 'Wed, 21 Oct 2026 07:28:00 GMT',
        createdAt: DateTime(2026, 11, 1),
        segments: const [
          DownloadSegment(
            index: 0,
            startByte: 0,
            endByte: 999,
            downloadedBytes: 500,
          ),
          DownloadSegment(
            index: 1,
            startByte: 1000,
            endByte: 1999,
            downloadedBytes: 0,
          ),
        ],
      );

      // Save single task
      await repo.saveTask(task);

      // Load tasks
      final loaded = await repo.loadTasks();
      expect(loaded.length, equals(1));
      expect(loaded.first.id, equals('task_1'));
      expect(loaded.first.fileName, equals('file.iso'));
      expect(loaded.first.totalBytes, equals(2000));
      expect(loaded.first.downloadedBytes, equals(500));
      // Status downloading is sanitized to paused on load for safety
      expect(loaded.first.status, equals(DownloadStatus.paused));
      expect(loaded.first.etag, equals('"abc123etag"'));
      expect(loaded.first.segments.length, equals(2));
      expect(loaded.first.segments[0].downloadedBytes, equals(500));
      expect(loaded.first.segments[1].startByte, equals(1000));

      // Update single task
      final updated = task.copyWith(
        downloadedBytes: 1500,
        status: DownloadStatus.paused,
        segments: const [
          DownloadSegment(
            index: 0,
            startByte: 0,
            endByte: 999,
            downloadedBytes: 1000,
            isCompleted: true,
          ),
          DownloadSegment(
            index: 1,
            startByte: 1000,
            endByte: 1999,
            downloadedBytes: 500,
          ),
        ],
      );
      await repo.saveTask(updated);

      final reloaded = await repo.loadTasks();
      expect(reloaded.first.downloadedBytes, equals(1500));
      expect(reloaded.first.segments[0].isCompleted, isTrue);

      // Delete task
      await repo.deleteTask('task_1');
      final afterDelete = await repo.loadTasks();
      expect(afterDelete, isEmpty);

      await repo.close();
    },
  );

  test(
    'SqliteDownloadRepository migrates netget_tasks.json with .bak safety',
    () async {
      // Create a legacy netget_tasks.json file
      final legacyFile = File(p.join(tempDir.path, 'netget_tasks.json'));
      final initialLegacyTasks = [
        {
          'id': 'legacy_1',
          'url': 'https://example.com/legacy.zip',
          'fileName': 'legacy.zip',
          'savePath': '/downloads/legacy.zip',
          'totalBytes': 5000,
          'downloadedBytes': 2500,
          'status': 'downloading',
          'resumable': true,
          'speedBytesPerSec': 12345.0,
          'createdAt': '2026-10-15T12:00:00.000Z',
          'category': 'archive',
          'connectionCount': 4,
          'etag': '"legacy-etag"',
          'queueName': 'Default',
          'segments': [
            {
              'index': 0,
              'startByte': 0,
              'endByte': 2499,
              'downloadedBytes': 2500,
              'isCompleted': true,
            },
            {
              'index': 1,
              'startByte': 2500,
              'endByte': 4999,
              'downloadedBytes': 0,
              'isCompleted': false,
            },
          ],
        },
      ];
      await legacyFile.writeAsString(jsonEncode(initialLegacyTasks));

      final repo = SqliteDownloadRepository(
        customDbPath: dbPath,
        jsonMigrationSource: legacyFile,
      );

      // Trigger open and migration
      final tasks = await repo.loadTasks();
      expect(tasks.length, equals(1));
      expect(tasks.first.id, equals('legacy_1'));
      expect(tasks.first.fileName, equals('legacy.zip'));
      expect(tasks.first.totalBytes, equals(5000));
      expect(tasks.first.segments.length, equals(2));

      // Verify .bak file was created
      final bakFile = File('${legacyFile.path}.bak');
      expect(
        await bakFile.exists(),
        isTrue,
        reason: '.bak backup file must be preserved',
      );

      // Verify original json was renamed to .migrated
      expect(
        await legacyFile.exists(),
        isFalse,
        reason: 'Original json must be renamed to .migrated',
      );
      final migratedFile = File('${legacyFile.path}.migrated');
      expect(
        await migratedFile.exists(),
        isTrue,
        reason: '.migrated file must exist',
      );

      await repo.close();
    },
  );
}
