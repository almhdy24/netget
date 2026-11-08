import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/segment_planner.dart';
import 'package:netget/data/download_repository.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/download_manager.dart';
import '../../tool/test_http_server.dart';

class InMemoryTaskRepository implements DownloadRepository {
  List<DownloadTask> tasks = [];
  int saveCount = 0;

  @override
  Future<List<DownloadTask>> loadTasks() async => List.from(tasks);

  @override
  Future<void> saveTasks(List<DownloadTask> newTasks) async {
    saveCount++;
    tasks = List.from(newTasks);
  }

  @override
  Future<void> saveTask(DownloadTask task) async {
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx >= 0) {
      tasks[idx] = task;
    } else {
      tasks.add(task);
    }
  }

  @override
  Future<void> deleteTask(String id) async {
    tasks.removeWhere((t) => t.id == id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late TestHttpServer server;
  late Directory tempDir;

  setUpAll(() async {
    server = TestHttpServer(dataSize: 2 * 1024 * 1024); // 2 MB
    await server.start();
  });

  tearDownAll(() async {
    await server.stop();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_restart_safety_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'Restart Safety: Preallocated file with holes is NOT marked complete on resume without verified segments',
    () async {
      final saveFile = File('${tempDir.path}/sparse_preallocated.bin');
      final totalSize = server.testData.length;

      // 1. Create a preallocated file on disk where length == totalBytes, but it contains holes (zeros)
      final raf = await saveFile.open(mode: FileMode.write);
      await raf.truncate(totalSize);
      // Write only first 128 KB
      await raf.setPosition(0);
      await raf.writeFrom(server.testData.sublist(0, 128 * 1024));
      await raf.close();

      expect(
        await saveFile.length(),
        equals(totalSize),
        reason: 'Disk file length is already 2 MB',
      );

      final repo = InMemoryTaskRepository();
      // 2. Create task state with partial segment progress (segments incomplete)
      final segments = SegmentPlanner.planInitialSegments(
        totalBytes: totalSize,
        connectionCount: 4,
        resumable: true,
      );
      // Only segment 0 downloaded 128 KB
      segments[0] = segments[0].copyWith(downloadedBytes: 128 * 1024);

      final initialTask = DownloadTask(
        id: 'task_sparse_resume',
        url: 'http://127.0.0.1:${server.actualPort}/download',
        fileName: 'sparse_preallocated.bin',
        savePath: saveFile.path,
        totalBytes: totalSize,
        downloadedBytes: 128 * 1024,
        status: DownloadStatus.paused,
        resumable: true,
        connectionCount: 4,
        etag: server.etag,
        createdAt: DateTime.now(),
        segments: segments,
      );
      repo.tasks = [initialTask];

      // 3. Create a brand-new DownloadManager instance loading this persisted task
      final manager = DownloadManager(
        repository: repo,
        downloadsDirResolver: () async => tempDir,
      );
      await manager.init();

      // Verify task is loaded as paused, NOT completed
      expect(manager.tasks.first.status, equals(DownloadStatus.paused));

      // 4. Resume download
      await manager.resumeDownload('task_sparse_resume');

      // Wait until download completes
      while (manager.tasks.first.status == DownloadStatus.downloading ||
          manager.tasks.first.status == DownloadStatus.queued) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      final finishedTask = manager.tasks.first;
      expect(finishedTask.status, equals(DownloadStatus.completed));
      expect(finishedTask.downloadedBytes, equals(totalSize));
      expect(
        finishedTask.segments.every((s) => s.isFinished && s.isCompleted),
        isTrue,
      );

      // 5. Verify file integrity (zero unwritten holes remaining)
      final fileBytes = await saveFile.readAsBytes();
      expect(fileBytes.length, equals(totalSize));
      expect(fileBytes, equals(server.testData));

      manager.dispose();
    },
  );

  test(
    'Restart Safety: Preallocated file with missing segment records restarts cleanly from byte 0',
    () async {
      final saveFile = File('${tempDir.path}/sparse_no_segments.bin');
      final totalSize = server.testData.length;

      // Preallocate file to totalBytes on disk
      final raf = await saveFile.open(mode: FileMode.write);
      await raf.truncate(totalSize);
      await raf.close();

      expect(await saveFile.length(), equals(totalSize));

      final repo = InMemoryTaskRepository();
      // Task with missing segments in JSON (segments: [])
      final initialTask = DownloadTask(
        id: 'task_no_segments',
        url: 'http://127.0.0.1:${server.actualPort}/download',
        fileName: 'sparse_no_segments.bin',
        savePath: saveFile.path,
        totalBytes: totalSize,
        downloadedBytes: 500000,
        status: DownloadStatus.paused,
        resumable: true,
        connectionCount: 4,
        etag: server.etag,
        createdAt: DateTime.now(),
        segments: const [], // Missing segments!
      );
      repo.tasks = [initialTask];

      final manager = DownloadManager(
        repository: repo,
        downloadsDirResolver: () async => tempDir,
      );
      await manager.init();

      await manager.resumeDownload('task_no_segments');

      while (manager.tasks.first.status == DownloadStatus.downloading ||
          manager.tasks.first.status == DownloadStatus.queued) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      final finishedTask = manager.tasks.first;
      expect(finishedTask.status, equals(DownloadStatus.completed));
      expect(finishedTask.downloadedBytes, equals(totalSize));

      final fileBytes = await saveFile.readAsBytes();
      expect(fileBytes, equals(server.testData));

      manager.dispose();
    },
  );

  test(
    'Restart Safety: ETag changed after restart triggers clean restart from byte 0 and SHA-256 match',
    () async {
      final saveFile = File('${tempDir.path}/sparse_etag_change.bin');
      final totalSize = server.testData.length;

      final raf = await saveFile.open(mode: FileMode.write);
      await raf.truncate(totalSize);
      await raf.close();

      final repo = InMemoryTaskRepository();
      // Task paused with stale ETag
      final initialTask = DownloadTask(
        id: 'task_etag_changed',
        // Request etag_changed mode from test server
        url: 'http://127.0.0.1:${server.actualPort}/download?mode=etag_changed',
        fileName: 'sparse_etag_change.bin',
        savePath: saveFile.path,
        totalBytes: totalSize,
        downloadedBytes: 256 * 1024,
        status: DownloadStatus.paused,
        resumable: true,
        connectionCount: 4,
        etag: server.etag, // stale initial ETag
        createdAt: DateTime.now(),
        segments: SegmentPlanner.planInitialSegments(
          totalBytes: totalSize,
          connectionCount: 4,
          resumable: true,
        ),
      );
      repo.tasks = [initialTask];

      final manager = DownloadManager(
        repository: repo,
        downloadsDirResolver: () async => tempDir,
      );
      await manager.init();

      await manager.resumeDownload('task_etag_changed');

      while (manager.tasks.first.status == DownloadStatus.downloading ||
          manager.tasks.first.status == DownloadStatus.queued) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      final finishedTask = manager.tasks.first;
      expect(finishedTask.status, equals(DownloadStatus.completed));

      // File was downloaded completely and matches server payload
      final fileBytes = await saveFile.readAsBytes();
      expect(fileBytes.length, equals(totalSize));
      expect(fileBytes, equals(server.testData));

      manager.dispose();
    },
  );
}
