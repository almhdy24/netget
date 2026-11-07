import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/data/download_repository.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/download_manager.dart';

class MockRepo implements DownloadRepository {
  List<DownloadTask> inMemory = [];

  @override
  Future<List<DownloadTask>> loadTasks() async => List.from(inMemory);

  @override
  Future<void> saveTasks(List<DownloadTask> tasks) async {
    inMemory = List.from(tasks);
  }

  @override
  Future<void> saveTask(DownloadTask task) async {
    final idx = inMemory.indexWhere((t) => t.id == task.id);
    if (idx >= 0) {
      inMemory[idx] = task;
    } else {
      inMemory.insert(0, task);
    }
  }

  @override
  Future<void> deleteTask(String id) async {
    inMemory.removeWhere((t) => t.id == id);
  }
}

void main() {
  group('Stale Error Bug Fix Verification', () {
    test('DownloadTask.copyWith clears errorMessage when clearError: true or transitioning to active status', () {
      final failedTask = DownloadTask(
        id: '1',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        savePath: '/tmp/file.zip',
        status: DownloadStatus.failed,
        errorMessage: 'Connection timed out',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(failedTask.errorMessage, 'Connection timed out');

      // 1) Explicit clearError: true
      final clearedTaskExplicit = failedTask.copyWith(
        clearError: true,
      );
      expect(clearedTaskExplicit.errorMessage, isNull);

      // 2) Transitioning to queued with errorMessage: null
      final clearedTaskQueued = failedTask.copyWith(
        status: DownloadStatus.queued,
        errorMessage: null,
      );
      expect(clearedTaskQueued.errorMessage, isNull);

      // 3) Transitioning to downloading with errorMessage: null
      final clearedTaskDownloading = failedTask.copyWith(
        status: DownloadStatus.downloading,
      );
      expect(clearedTaskDownloading.errorMessage, isNull);

      // 4) Transitioning to completed with errorMessage: null
      final clearedTaskCompleted = failedTask.copyWith(
        status: DownloadStatus.completed,
      );
      expect(clearedTaskCompleted.errorMessage, isNull);

      // 5) Explicitly passing a new non-null error keeps the new error
      final updatedErrorTask = failedTask.copyWith(
        errorMessage: 'New 404 error',
      );
      expect(updatedErrorTask.errorMessage, 'New 404 error');
    });

    test('fail -> retry -> downloading shows no error; persisted JSON has no stale error', () async {
      final repo = MockRepo();
      final manager = DownloadManager(repository: repo);

      // Preload a task that failed with timeout
      final failedTask = DownloadTask(
        id: 'task_err',
        url: 'https://example.com/timeout.bin',
        fileName: 'timeout.bin',
        savePath: '/tmp/timeout.bin',
        status: DownloadStatus.failed,
        errorMessage: 'Connection timed out after 30s',
        createdAt: DateTime(2026, 1, 1),
      );
      repo.inMemory = [failedTask];
      await manager.init();

      expect(manager.tasks.first.errorMessage, 'Connection timed out after 30s');

      // User retries download
      await manager.retryDownload('task_err');

      final taskAfterRetry = manager.tasks.first;
      // Task immediately queued or downloading
      expect(taskAfterRetry.status.isActive, isTrue);
      expect(taskAfterRetry.errorMessage, isNull,
          reason: 'Retried task must have cleared errorMessage');

      // Check persisted repository
      expect(repo.inMemory.first.errorMessage, isNull,
          reason: 'Persisted task in repo must have cleared errorMessage');

      // Check serialized JSON
      final json = repo.inMemory.first.toJson();
      expect(json['errorMessage'], isNull,
          reason: 'Persisted JSON must not retain stale errorMessage');
    });

    test('fail -> retry -> fail again shows the NEW error', () async {
      final repo = MockRepo();
      final manager = DownloadManager(repository: repo);

      final initialFailed = DownloadTask(
        id: 'task_retry',
        url: 'https://example.com/test.bin',
        fileName: 'test.bin',
        savePath: '/tmp/test.bin',
        status: DownloadStatus.failed,
        errorMessage: 'Initial error: Network timeout',
        createdAt: DateTime(2026, 1, 1),
      );
      repo.inMemory = [initialFailed];
      await manager.init();

      // Retry
      await manager.retryDownload('task_retry');
      expect(manager.tasks.first.errorMessage, isNull);

      // Trigger new failure
      manager.setTaskFailureForTesting('task_retry', 'New error: HTTP 404 Not Found');

      expect(manager.tasks.first.errorMessage, 'New error: HTTP 404 Not Found');
    });
  });
}
