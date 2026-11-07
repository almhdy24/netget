import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/constants.dart';
import 'package:netget/data/download_repository.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/download_manager.dart';

class InMemoryRepo implements DownloadRepository {
  List<DownloadTask> tasks = [];
  @override
  Future<List<DownloadTask>> loadTasks() async => List.from(tasks);
  @override
  Future<void> saveTasks(List<DownloadTask> t) async => tasks = List.from(t);
  @override
  Future<void> saveTask(DownloadTask t) async => tasks.add(t);
  @override
  Future<void> deleteTask(String id) async =>
      tasks.removeWhere((x) => x.id == id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryRepo repo;
  late DownloadManager manager;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_desktop_test');
    repo = InMemoryRepo();
    manager = DownloadManager(
      repository: repo,
      downloadsDirResolver: () async => tempDir,
    );
    await manager.init();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Desktop Features in DownloadManager', () {
    test('detects duplicate URLs accurately', () async {
      await manager.addDownload(
        url: 'https://example.com/unique.zip',
        startNow: false,
      );

      final found = manager.findTaskByUrl('https://example.com/unique.zip');
      expect(found, isNotNull);
      expect(found!.url, 'https://example.com/unique.zip');

      final notFound = manager.findTaskByUrl('https://example.com/other.zip');
      expect(notFound, isNull);
    });

    test('event log records in-memory ring buffer (up to 200 items)', () {
      const taskId = 'task_log_test';
      for (var i = 1; i <= 250; i++) {
        manager.logEvent(taskId, 'INFO', 'Event $i');
      }

      final logs = manager.getTaskLogs(taskId);
      expect(logs.length, 200);
      expect(logs.first.message, 'Event 51');
      expect(logs.last.message, 'Event 250');
    });

    test(
      'watchTaskDetails emits live snapshots including segments and samples',
      () async {
        final task = await manager.addDownload(
          url: 'https://example.com/stream.zip',
          startNow: false,
          connectionCount: 4,
        );

        final stream = manager.watchTaskDetails(task.id);
        final update = await stream.first;

        expect(update.task.id, task.id);
        expect(update.segments, isNotEmpty);
        expect(update.task.connectionCount, 4);
      },
    );

    test('speed mode updates global limiter mode', () {
      expect(manager.speedMode, SpeedMode.unlimited);
      manager.setSpeedMode(SpeedMode.high);
      expect(manager.speedMode, SpeedMode.high);
      expect(manager.speedMode.bytesPerSec, 5 * 1024 * 1024);
    });

    test(
      'queue scheduler stores and retrieves automated start/stop schedule',
      () {
        const schedule = QueueSchedule(
          queueName: 'Main',
          startHour: 2,
          startMinute: 30,
          stopHour: 6,
          stopMinute: 0,
          isEnabled: true,
        );

        manager.setQueueSchedule(schedule);

        final retrieved = manager.getQueueSchedule('Main');
        expect(retrieved, isNotNull);
        expect(retrieved!.formattedStartTime, '02:30');
        expect(retrieved.formattedStopTime, '06:00');
        expect(retrieved.isEnabled, isTrue);
      },
    );
  });
}
