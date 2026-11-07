import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/download_failure.dart';
import 'package:netget/data/download_repository.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/download_manager.dart';
import 'package:netget/services/multi_connection_downloader.dart';

class _FakeFailureRepo implements DownloadRepository {
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
  group('DownloadFailureMapper Tests', () {
    test('maps TimeoutException to timeout code', () {
      final code = DownloadFailureMapper.mapException(
        TimeoutException('Connection timed out'),
      );
      expect(code, equals(DownloadFailureCode.timeout));
      expect(code.localizedMessage(), equals('Connection timed out'));
      expect(code.localizedMessage(isArabic: true), equals('انتهت مهلة الاتصال'));
    });

    test('maps SocketException to serverRefused when refused', () {
      final code = DownloadFailureMapper.mapException(
        const SocketException('Connection refused', osError: OSError('Connection refused', 111)),
      );
      expect(code, equals(DownloadFailureCode.serverRefused));
      expect(code.localizedMessage(), equals('Server refused connection'));
      expect(code.localizedMessage(isArabic: true), equals('رفض الخادم الاتصال'));
    });

    test('maps SocketException to noConnection when network fails', () {
      final code = DownloadFailureMapper.mapException(
        const SocketException('Failed host lookup: example.com'),
      );
      expect(code, equals(DownloadFailureCode.noConnection));
      expect(code.localizedMessage(), contains('No connection'));
      expect(code.localizedMessage(isArabic: true), contains('لا يوجد اتصال'));
    });

    test('maps storage / disk space errors to storageFull', () {
      final code1 = DownloadFailureMapper.mapException(
        const FileSystemException('Write failed', '', OSError('No space left on device', 28)),
      );
      expect(code1, equals(DownloadFailureCode.storageFull));
      expect(code1.localizedMessage(), equals('Storage is full'));

      final code2 = DownloadFailureMapper.mapException(
        DiskSpaceException('Storage space is exhausted'),
      );
      expect(code2, equals(DownloadFailureCode.storageFull));
    });

    test('maps HTTP 403, 404, and 500 errors', () {
      final c403 = DownloadFailureMapper.mapException(const HttpException('403 Forbidden'));
      expect(c403, equals(DownloadFailureCode.http403));
      expect(c403.localizedMessage(), contains('403'));

      final c404 = DownloadFailureMapper.mapException(const HttpException('404 Not Found'));
      expect(c404, equals(DownloadFailureCode.http404));
      expect(c404.localizedMessage(), contains('404'));

      final c500 = DownloadFailureMapper.mapException(const HttpException('500 Internal Server Error'));
      expect(c500, equals(DownloadFailureCode.serverError));
    });

    test('maps file changed on server (ETag mutation)', () {
      final code = DownloadFailureMapper.mapException(
        Exception('ETag mutated from "old" to "new" during resume'),
      );
      expect(code, equals(DownloadFailureCode.fileChangedOnServer));
      expect(code.localizedMessage(), equals('File changed on server'));
      expect(code.localizedMessage(isArabic: true), equals('تغير الملف على الخادم'));
    });
  });

  group('DownloadManager Failure UX & Auto-retry Tests', () {
    late _FakeFailureRepo repo;
    late DownloadManager manager;

    setUp(() {
      repo = _FakeFailureRepo();
      manager = DownloadManager(repository: repo);
    });

    tearDown(() {
      manager.dispose();
    });

    test('records raw exception in event log while presenting clean error to user', () async {
      final task = DownloadTask(
        id: 'fail_task_1',
        url: 'https://example.com/test.bin',
        fileName: 'test.bin',
        savePath: '/tmp/test.bin',
        status: DownloadStatus.downloading,
        totalBytes: 1000,
        downloadedBytes: 100,
        createdAt: DateTime(2026, 1, 1),
      );
      repo.inMemory.add(task);
      await manager.init();

      // Trigger failure with SocketException
      const rawError = SocketException('Failed host lookup: example.com');
      final failureCode = DownloadFailureMapper.mapException(rawError);
      final cleanMsg = failureCode.localizedMessage();

      manager.setTaskFailureForTesting(task.id, cleanMsg);
      manager.logEvent(task.id, 'ERROR', 'Error ($failureCode): $rawError');

      final updatedTask = manager.tasks.firstWhere((t) => t.id == task.id);
      expect(updatedTask.status, equals(DownloadStatus.failed));
      expect(updatedTask.errorMessage, equals(cleanMsg));
      expect(updatedTask.errorMessage, isNot(contains('SocketException')));

      final logs = manager.getTaskLogs(task.id);
      expect(logs.any((l) => l.level == 'ERROR' && l.message.contains('SocketException')), isTrue);
    });
  });
}
