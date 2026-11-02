import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/data/download_repository.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/download_manager.dart';

class MockDownloadRepository implements DownloadRepository {
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

class DummyHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return DummyHttpRequest();
  }

  @override
  void close({bool force = false}) {}
}

class DummyHttpRequest implements HttpClientRequest {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final HttpHeaders _headers = DummyHttpHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() {
    // Keep pending request to simulate active in-flight transfer
    return Completer<HttpClientResponse>().future;
  }
}

class DummyHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final Map<String, dynamic> _data = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _data[name] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDownloadRepository repository;
  late DownloadManager manager;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_mgr_test');
    repository = MockDownloadRepository();
    manager = DownloadManager(
      repository: repository,
      clientFactory: () => DummyHttpClient(),
      downloadsDirResolver: () async => tempDir,
    );
    await manager.init();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DownloadManager', () {
    test('throws ArgumentError on invalid URLs', () async {
      expect(
        () => manager.addDownload(url: ''),
        throwsArgumentError,
      );
      expect(
        () => manager.addDownload(url: 'ftp://ftp.example.com/file.zip'),
        throwsArgumentError,
      );
      expect(
        () => manager.addDownload(url: 'not-a-valid-url'),
        throwsArgumentError,
      );
    });

    test('addDownload adds task, transitions to downloading, and persists', () async {
      final task = await manager.addDownload(
        url: 'https://example.com/test.zip',
        customFileName: 'custom.zip',
      );

      expect(task.fileName, 'custom.zip');
      expect(task.url, 'https://example.com/test.zip');
      expect(manager.tasks.length, 1);
      expect(repository.inMemory.length, 1);
      expect(manager.tasks.first.status, DownloadStatus.downloading);
    });

    test('pauseDownload transitions task to paused state', () async {
      final task = await manager.addDownload(
        url: 'https://example.com/test.zip',
      );

      expect(manager.tasks.first.status, DownloadStatus.downloading);

      await manager.pauseDownload(task.id);

      final updated = manager.tasks.firstWhere((t) => t.id == task.id);
      expect(updated.status, DownloadStatus.paused);
      expect(updated.speedBytesPerSec, 0.0);
    });

    test('resumeDownload resets status to queued / downloading', () async {
      final task = await manager.addDownload(
        url: 'https://example.com/test.zip',
      );
      await manager.pauseDownload(task.id);
      expect(manager.tasks.first.status, DownloadStatus.paused);

      await manager.resumeDownload(task.id);

      final updated = manager.tasks.firstWhere((t) => t.id == task.id);
      expect(
        updated.status == DownloadStatus.queued ||
            updated.status == DownloadStatus.downloading,
        isTrue,
      );
    });

    test('cancelDownload transitions status to cancelled', () async {
      final task = await manager.addDownload(
        url: 'https://example.com/test.zip',
      );

      await manager.cancelDownload(task.id);

      final updated = manager.tasks.firstWhere((t) => t.id == task.id);
      expect(updated.status, DownloadStatus.cancelled);
    });

    test('deleteTask removes task from manager and repository', () async {
      final task = await manager.addDownload(
        url: 'https://example.com/test.zip',
      );
      expect(manager.tasks.length, 1);

      await manager.deleteTask(task.id);
      expect(manager.tasks, isEmpty);
      expect(repository.inMemory, isEmpty);
    });

    test('clearCompleted clears only finished tasks', () async {
      final task1 = DownloadTask(
        id: '1',
        url: 'https://example.com/done.zip',
        fileName: 'done.zip',
        savePath: '/tmp/done.zip',
        status: DownloadStatus.completed,
        createdAt: DateTime(2026, 1, 1),
      );
      final task2 = DownloadTask(
        id: '2',
        url: 'https://example.com/paused.zip',
        fileName: 'paused.zip',
        savePath: '/tmp/paused.zip',
        status: DownloadStatus.paused,
        createdAt: DateTime(2026, 1, 1),
      );

      repository.inMemory = [task1, task2];
      await manager.init(forceReload: true);

      expect(manager.completedTasks.length, 1);
      await manager.clearCompleted();

      expect(manager.completedTasks, isEmpty);
      expect(manager.tasks.length, 1);
      expect(manager.tasks.first.id, '2');
    });

    test('handles network exceptions gracefully and records failure message', () async {
      final errorManager = DownloadManager(
        repository: repository,
        clientFactory: () => throw const SocketException('Connection refused by host'),
        downloadsDirResolver: () async => tempDir,
      );
      await errorManager.init();

      final task = await errorManager.addDownload(
        url: 'https://example.com/fail.zip',
      );

      // Wait a microtask tick for async _startDownloading to catch exception
      await Future.delayed(const Duration(milliseconds: 50));

      final failed = errorManager.tasks.firstWhere((t) => t.id == task.id);
      expect(failed.status, DownloadStatus.failed);
      expect(failed.errorMessage, contains('Connection refused'));
    });
  });
}
