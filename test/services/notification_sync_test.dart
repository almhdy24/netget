import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/data/download_repository.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/download_manager.dart';

class _FakeSyncRepo implements DownloadRepository {
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
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.elmahdi.netget/engine');
  late List<MethodCall> methodCalls;

  setUp(() {
    methodCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      methodCalls.add(call);
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('Notification Progress Bar & Sync Payload Tests', () {
    test('sends count, percent, and file name when single download is active', () async {
      final repo = _FakeSyncRepo();
      final manager = DownloadManager(repository: repo);
      manager.isAndroidForTesting = true;

      final task = DownloadTask(
        id: 't1',
        url: 'https://example.com/single.mp4',
        fileName: 'single.mp4',
        savePath: '/tmp/single.mp4',
        status: DownloadStatus.downloading,
        downloadedBytes: 50,
        totalBytes: 100,
        createdAt: DateTime(2026, 1, 1),
      );
      repo.inMemory.add(task);
      await manager.init();

      // Trigger sync
      manager.notifyListeners();

      final calls = methodCalls.where((c) => c.method == 'updateActiveDownloads').toList();
      expect(calls, isNotEmpty);
      final lastPayload = calls.last.arguments as Map;

      expect(lastPayload['activeCount'], equals(1));
      expect(lastPayload['name'], equals('single.mp4'));
      expect(lastPayload['percent'], equals(50));
      expect(lastPayload['totalBytes'], equals(100));

      manager.dispose();
    });

    test('sends aggregated count, aggregated percent, and empty name for multiple downloads', () async {
      final repo = _FakeSyncRepo();
      final manager = DownloadManager(repository: repo);
      manager.isAndroidForTesting = true;

      final t1 = DownloadTask(
        id: 't1',
        url: 'https://example.com/file1.zip',
        fileName: 'file1.zip',
        savePath: '/tmp/file1.zip',
        status: DownloadStatus.downloading,
        downloadedBytes: 25,
        totalBytes: 100,
        createdAt: DateTime(2026, 1, 1),
      );
      final t2 = DownloadTask(
        id: 't2',
        url: 'https://example.com/file2.zip',
        fileName: 'file2.zip',
        savePath: '/tmp/file2.zip',
        status: DownloadStatus.downloading,
        downloadedBytes: 75,
        totalBytes: 100,
        createdAt: DateTime(2026, 1, 1),
      );
      repo.inMemory.addAll([t1, t2]);
      await manager.init();

      manager.notifyListeners();

      final calls = methodCalls.where((c) => c.method == 'updateActiveDownloads').toList();
      expect(calls, isNotEmpty);
      final lastPayload = calls.last.arguments as Map;

      expect(lastPayload['activeCount'], equals(2));
      expect(lastPayload['name'], isEmpty);
      // sumDownloaded (100) / sumTotal (200) = 50%
      expect(lastPayload['percent'], equals(50));
      expect(lastPayload['totalBytes'], equals(200));

      manager.dispose();
    });

    test('throttles progress updates to at most once per second', () async {
      final repo = _FakeSyncRepo();
      final manager = DownloadManager(repository: repo);
      manager.isAndroidForTesting = true;

      var currentTime = DateTime(2026, 1, 1, 12, 0, 0);
      manager.clock = () => currentTime;

      final task = DownloadTask(
        id: 't_throttle',
        url: 'https://example.com/file.bin',
        fileName: 'file.bin',
        savePath: '/tmp/file.bin',
        status: DownloadStatus.downloading,
        downloadedBytes: 10,
        totalBytes: 100,
        createdAt: DateTime(2026, 1, 1),
      );
      repo.inMemory.add(task);
      await manager.init();

      // First notify triggers transition (0 -> 1 count)
      manager.notifyListeners();
      final countBefore = methodCalls.where((c) => c.method == 'updateActiveDownloads').length;
      expect(countBefore, equals(1));

      // Advance clock by only 200ms and notify again
      currentTime = currentTime.add(const Duration(milliseconds: 200));
      manager.notifyListeners();

      // No new method call because throttled (< 1000ms)
      final countAfter200ms = methodCalls.where((c) => c.method == 'updateActiveDownloads').length;
      expect(countAfter200ms, equals(countBefore));

      // Advance clock by another 900ms (total 1100ms > 1000ms)
      currentTime = currentTime.add(const Duration(milliseconds: 900));
      manager.notifyListeners();

      // New call sent because > 1000ms elapsed
      final countAfter1100ms = methodCalls.where((c) => c.method == 'updateActiveDownloads').length;
      expect(countAfter1100ms, equals(countBefore + 1));

      manager.dispose();
    });
  });
}
