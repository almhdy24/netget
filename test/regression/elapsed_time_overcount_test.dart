import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/download_manager.dart';
import 'package:netget/data/download_repository.dart';

class InMemoryRepo implements DownloadRepository {
  List<DownloadTask> tasks = [];
  @override
  Future<List<DownloadTask>> loadTasks() async => List.from(tasks);
  @override
  Future<void> saveTasks(List<DownloadTask> list) async {
    tasks = List.from(list);
  }

  @override
  Future<void> saveTask(DownloadTask task) async {
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx >= 0) {
      tasks[idx] = task;
    } else {
      tasks.insert(0, task);
    }
  }

  @override
  Future<void> deleteTask(String id) async {
    tasks.removeWhere((t) => t.id == id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CHARACTERIZATION: Elapsed time increments by 1 per tick rather than active wall-clock seconds (4x overcount)',
    () async {
      final repo = InMemoryRepo();
      final tempDir = await Directory.systemTemp.createTemp(
        'elapsed_time_test',
      );
      final manager = DownloadManager(
        repository: repo,
        downloadsDirResolver: () async => tempDir,
      );
      await manager.init();

      try {
        final task = await manager.addDownload(
          url: 'http://example.com/file.zip',
          startNow: false,
        );

        // Manually put task into downloading state for progress ticks
        await manager.resumeDownload(task.id);

        // Simulate 4 progress ticks occurring within 1 second (250ms intervals)
        manager.emitProgressTick(task.id, downloadedBytes: 100);
        manager.emitProgressTick(task.id, downloadedBytes: 200);
        manager.emitProgressTick(task.id, downloadedBytes: 300);
        manager.emitProgressTick(task.id, downloadedBytes: 400);

        final updatedTask = manager.tasks.firstWhere((t) => t.id == task.id);

        // In buggy code: elapsedSeconds is 4 (incremented by 1 per tick, not 1s of active time)
        // In fixed engine: 4 ticks in 1 second must not count as 4 seconds elapsed!
        expect(
          updatedTask.elapsedSeconds,
          lessThanOrEqualTo(1),
          reason:
              '4 sub-second progress ticks within 1 real second must not count as 4 seconds elapsed',
        );
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );
}
