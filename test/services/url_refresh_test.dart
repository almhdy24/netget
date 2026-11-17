import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/data/download_repository.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/download_manager.dart';
import '../support/test_server.dart';

class _InMemoryRepo implements DownloadRepository {
  final Map<String, DownloadTask> tasks = {};

  @override
  Future<List<DownloadTask>> loadTasks() async => tasks.values.toList();

  @override
  Future<void> saveTasks(List<DownloadTask> taskList) async {
    tasks.clear();
    for (final t in taskList) {
      tasks[t.id] = t;
    }
  }

  @override
  Future<void> saveTask(DownloadTask task) async {
    tasks[task.id] = task;
  }

  @override
  Future<void> deleteTask(String id) async {
    tasks.remove(id);
  }
}

void main() {
  late Directory tempDir;
  late _InMemoryRepo repo;
  late DownloadManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_refresh_test_');
    repo = _InMemoryRepo();
    manager = DownloadManager(
      repository: repo,
      downloadsDirResolver: () async => tempDir,
    );
    await manager.init();
  });

  tearDown(() async {
    manager.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('403 Forbidden pauses task with urlExpired reason', () async {
    final server = NetGetTestServer();
    server.statusInjectionByRequest[1] = 403;
    server.statusInjectionByRequest[2] = 403;
    await server.start();

    try {
      final task = await manager.addDownload(
        url: server.downloadUri.toString(),
        startNow: true,
      );

      // Wait for the download attempt to encounter 403
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final updated = manager.tasks.firstWhere((t) => t.id == task.id);
      expect(updated.status, equals(DownloadStatus.paused));
      expect(updated.pauseReason, equals('urlExpired'));
      expect(updated.errorMessage, contains('Link expired'));
    } finally {
      await server.stop();
    }
  });

  test('refreshTaskUrl validates and updates URL when file matches', () async {
    const fileBytes = 512 * 1024;
    final expiredServer = NetGetTestServer(dataSize: fileBytes);
    expiredServer.statusInjectionByRequest[1] = 403;
    expiredServer.statusInjectionByRequest[2] = 403;
    await expiredServer.start();

    final validServer = NetGetTestServer(
      dataSize: fileBytes,
      strongEtag: '"match-etag"',
      validatorMode: ValidatorMode.strongEtag,
    );
    await validServer.start();

    try {
      final task = await manager.addDownload(
        url: expiredServer.downloadUri.toString(),
        startNow: true,
        totalBytes: fileBytes,
        etag: '"match-etag"',
      );

      await Future<void>.delayed(const Duration(milliseconds: 400));
      final expiredTask = manager.tasks.firstWhere((t) => t.id == task.id);
      expect(expiredTask.pauseReason, equals('urlExpired'));

      // Refresh link with matching valid URL
      await manager.refreshTaskUrl(task.id, validServer.downloadUri.toString());

      final refreshedTask = manager.tasks.firstWhere((t) => t.id == task.id);
      expect(refreshedTask.url, equals(validServer.downloadUri.toString()));
      expect(refreshedTask.pauseReason, isNull);
      expect(refreshedTask.errorMessage, isNull);
    } finally {
      await expiredServer.stop();
      await validServer.stop();
    }
  });

  test('refreshTaskUrl rejects mismatched size unless forced', () async {
    const oldSize = 512 * 1024;
    const newSize = 1024 * 1024;

    final oldServer = NetGetTestServer(
      dataSize: oldSize,
      strongEtag: '"etag-1"',
      validatorMode: ValidatorMode.strongEtag,
    );
    await oldServer.start();

    final newServer = NetGetTestServer(
      dataSize: newSize,
      strongEtag: '"etag-2"',
      validatorMode: ValidatorMode.strongEtag,
    );
    await newServer.start();

    try {
      final task = await manager.addDownload(
        url: oldServer.downloadUri.toString(),
        startNow: false,
        totalBytes: oldSize,
        etag: '"etag-1"',
      );

      // Trying to refresh without force should throw size mismatch
      expect(
        () => manager.refreshTaskUrl(
          task.id,
          newServer.downloadUri.toString(),
          forceRestartIfMismatch: false,
        ),
        throwsA(predicate((e) => e.toString().contains('Size mismatch'))),
      );

      // With forceRestartIfMismatch: true, it resets and updates successfully
      await manager.refreshTaskUrl(
        task.id,
        newServer.downloadUri.toString(),
        forceRestartIfMismatch: true,
      );

      final updatedTask = manager.tasks.firstWhere((t) => t.id == task.id);
      expect(updatedTask.url, equals(newServer.downloadUri.toString()));
      expect(updatedTask.totalBytes, equals(newSize));
      expect(updatedTask.downloadedBytes, equals(0));
    } finally {
      await oldServer.stop();
      await newServer.stop();
    }
  });
}
