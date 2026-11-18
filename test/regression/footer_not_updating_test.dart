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
    'CHARACTERIZATION: DownloadManager does not notify listeners on progress ticks',
    () async {
      final repo = InMemoryRepo();
      final tempDir = await Directory.systemTemp.createTemp('footer_unit_test');
      final manager = DownloadManager(
        repository: repo,
        downloadsDirResolver: () async => tempDir,
      );
      await manager.init();

      try {
        final task = await manager.addDownload(
          url: 'http://example.com/test.zip',
          startNow: false,
        );
        await manager.resumeDownload(task.id);

        bool aggregateNotified = false;
        manager.addListener(() {
          aggregateNotified = true;
        });

        // Emit progress tick
        manager.emitProgressTick(
          task.id,
          downloadedBytes: 1024 * 1024,
          speedBytesPerSec: 5 * 1024 * 1024,
        );

        // In buggy code: manager only updates the task ValueNotifier, but NEVER notifies
        // its own aggregate listeners. Thus, aggregateNotified is false!
        // In fixed code: manager emits throttled aggregate updates so the footer and UI update!
        expect(
          aggregateNotified,
          isTrue,
          reason:
              'DownloadManager must notify listeners or aggregate stream during progress ticks',
        );
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );
}
