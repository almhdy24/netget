import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/download_manager.dart';
import 'package:netget/data/download_repository.dart';

class MockDownloadRepo implements DownloadRepository {
  List<DownloadTask> tasks = [];
  @override
  Future<List<DownloadTask>> loadTasks() async => List.from(tasks);
  @override
  Future<void> saveTasks(List<DownloadTask> newTasks) async {
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

  late MockDownloadRepo repo;
  late DownloadManager manager;
  final List<MethodCall> channelCalls = [];
  late StreamController<dynamic> fakeEventStream;
  late DateTime simulatedNow;

  setUp(() {
    channelCalls.clear();
    repo = MockDownloadRepo();
    simulatedNow = DateTime(2026, 11, 7, 12, 0, 0);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.elmahdi.netget/engine'),
      (MethodCall call) async {
        channelCalls.add(call);
        return true;
      },
    );

    fakeEventStream = StreamController<dynamic>.broadcast();

    manager = DownloadManager(repository: repo);
    manager.isAndroidForTesting = true;
    manager.clock = () => simulatedNow;
    manager.eventStreamForTesting = fakeEventStream.stream;
  });

  tearDown(() {
    manager.dispose();
    fakeEventStream.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.elmahdi.netget/engine'),
      null,
    );
  });

  test('Background keep-alive: 0 -> N transition immediately notifies native service', () async {
    await manager.init();

    expect(channelCalls.where((c) => c.method == 'updateActiveDownloads'), isEmpty);

    // Simulate task transitioning to downloading
    final task = DownloadTask(
      id: 'task_keepalive_1',
      url: 'https://example.com/test.zip',
      fileName: 'test.zip',
      savePath: '/tmp/test.zip',
      status: DownloadStatus.downloading,
      createdAt: simulatedNow,
      speedBytesPerSec: 1048576, // 1 MB/s
    );
    repo.tasks.add(task);
    await manager.init(forceReload: true);

    final keepaliveCalls = channelCalls.where((c) => c.method == 'updateActiveDownloads').toList();
    expect(keepaliveCalls.isNotEmpty, isTrue);
    final lastCall = keepaliveCalls.last;
    expect(lastCall.arguments['activeCount'], equals(1));
    expect(lastCall.arguments['progressText'], contains('MB/s'));
  });

  test('Background keep-alive: progress ticks are throttled to at most 1/s while downloading', () async {
    final task = DownloadTask(
      id: 'task_keepalive_2',
      url: 'https://example.com/test2.zip',
      fileName: 'test2.zip',
      savePath: '/tmp/test2.zip',
      status: DownloadStatus.downloading,
      createdAt: simulatedNow,
      speedBytesPerSec: 500000,
    );
    repo.tasks.add(task);
    await manager.init(forceReload: true);

    channelCalls.clear();

    // 10 rapid progress notifications within 200ms
    for (int i = 0; i < 10; i++) {
      simulatedNow = simulatedNow.add(const Duration(milliseconds: 20));
      manager.notifyListeners();
    }

    // Because activeCount remained 1 and elapsedMs < 1000, zero new MethodChannel calls emitted
    expect(channelCalls.where((c) => c.method == 'updateActiveDownloads'), isEmpty);

    // Advance clock past 1000ms threshold
    simulatedNow = simulatedNow.add(const Duration(milliseconds: 1100));
    manager.notifyListeners();

    final updates = channelCalls.where((c) => c.method == 'updateActiveDownloads').toList();
    expect(updates.length, equals(1));
    expect(updates.first.arguments['activeCount'], equals(1));
  });

  test('Background keep-alive: N -> 0 transition immediately notifies native service with activeCount = 0', () async {
    final task = DownloadTask(
      id: 'task_keepalive_3',
      url: 'https://example.com/test3.zip',
      fileName: 'test3.zip',
      savePath: '/tmp/test3.zip',
      status: DownloadStatus.downloading,
      createdAt: simulatedNow,
      speedBytesPerSec: 500000,
    );
    repo.tasks.add(task);
    await manager.init(forceReload: true);

    channelCalls.clear();

    // Pause all tasks (N -> 0 transition)
    await manager.pauseAll();

    final stopCalls = channelCalls.where((c) => c.method == 'updateActiveDownloads').toList();
    expect(stopCalls.isNotEmpty, isTrue);
    expect(stopCalls.last.arguments['activeCount'], equals(0));
    expect(stopCalls.last.arguments['progressText'], equals(''));
  });

  test('Background keep-alive: onTimeout event pauses all active downloads', () async {
    final task1 = DownloadTask(
      id: 'task_timeout_1',
      url: 'https://example.com/file1.zip',
      fileName: 'file1.zip',
      savePath: '/tmp/file1.zip',
      status: DownloadStatus.downloading,
      createdAt: simulatedNow,
    );
    final task2 = DownloadTask(
      id: 'task_timeout_2',
      url: 'https://example.com/file2.zip',
      fileName: 'file2.zip',
      savePath: '/tmp/file2.zip',
      status: DownloadStatus.downloading,
      createdAt: simulatedNow,
    );
    repo.tasks.addAll([task1, task2]);
    await manager.init(forceReload: true);

    expect(manager.tasks.every((t) => t.status == DownloadStatus.downloading), isTrue);

    // Native emits Android 15 dataSync timeout event
    fakeEventStream.add({'event': 'onTimeout'});
    await pumpEventQueue();

    expect(manager.tasks.every((t) => t.status == DownloadStatus.paused), isTrue);
  });
}
