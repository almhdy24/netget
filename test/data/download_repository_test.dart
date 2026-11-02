import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/data/download_repository.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';

void main() {
  late Directory tempDir;
  late File testFile;
  late JsonDownloadRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_repo_test');
    testFile = File('${tempDir.path}/tasks.json');
    repository = JsonDownloadRepository(file: testFile);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('JsonDownloadRepository', () {
    test('returns empty list when file does not exist', () async {
      final tasks = await repository.loadTasks();
      expect(tasks, isEmpty);
    });

    test('saves and loads tasks accurately', () async {
      final task1 = DownloadTask(
        id: '1',
        url: 'https://example.com/one.zip',
        fileName: 'one.zip',
        savePath: '/tmp/one.zip',
        status: DownloadStatus.completed,
        downloadedBytes: 1000,
        totalBytes: 1000,
        createdAt: DateTime(2026, 1, 1),
      );

      final task2 = DownloadTask(
        id: '2',
        url: 'https://example.com/two.mp4',
        fileName: 'two.mp4',
        savePath: '/tmp/two.mp4',
        status: DownloadStatus.paused,
        downloadedBytes: 500,
        totalBytes: 1500,
        createdAt: DateTime(2026, 1, 2),
      );

      await repository.saveTasks([task1, task2]);

      final loaded = await repository.loadTasks();
      expect(loaded.length, 2);
      expect(loaded[0].id, '1');
      expect(loaded[1].id, '2');
      expect(loaded[1].status, DownloadStatus.paused);
    });

    test('resets downloading status to paused on reload', () async {
      final task = DownloadTask(
        id: '3',
        url: 'https://example.com/in_progress.iso',
        fileName: 'in_progress.iso',
        savePath: '/tmp/in_progress.iso',
        status: DownloadStatus.downloading,
        downloadedBytes: 200,
        totalBytes: 1000,
        createdAt: DateTime(2026, 1, 1),
      );

      // Write directly to file with downloading status
      await repository.saveTasks([task]);

      final loaded = await repository.loadTasks();
      expect(loaded.first.status, DownloadStatus.paused);
      expect(loaded.first.speedBytesPerSec, 0.0);
    });

    test('deletes a task by id', () async {
      final task1 = DownloadTask(
        id: 'del_1',
        url: 'https://example.com/del1',
        fileName: 'del1',
        savePath: '/tmp/del1',
        createdAt: DateTime(2026, 1, 1),
      );
      final task2 = DownloadTask(
        id: 'del_2',
        url: 'https://example.com/del2',
        fileName: 'del2',
        savePath: '/tmp/del2',
        createdAt: DateTime(2026, 1, 1),
      );

      await repository.saveTasks([task1, task2]);
      await repository.deleteTask('del_1');

      final remaining = await repository.loadTasks();
      expect(remaining.length, 1);
      expect(remaining.first.id, 'del_2');
    });
  });
}
