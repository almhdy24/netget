import 'package:flutter_test/flutter_test.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';

void main() {
  group('DownloadTask', () {
    test('calculates progress and percentage accurately', () {
      final task = DownloadTask(
        id: '1',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        savePath: '/tmp/file.zip',
        totalBytes: 1000,
        downloadedBytes: 250,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(task.progress, closeTo(0.25, 0.001));
      expect(task.progressPercentage, '25.0%');
    });

    test('returns null progress when totalBytes is unknown (-1)', () {
      final task = DownloadTask(
        id: '1',
        url: 'https://example.com/stream',
        fileName: 'stream',
        savePath: '/tmp/stream',
        totalBytes: -1,
        downloadedBytes: 500,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(task.progress, isNull);
      expect(task.progressPercentage, isNull);
    });

    test('calculates ETA correctly based on speed', () {
      final task = DownloadTask(
        id: '1',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        savePath: '/tmp/file.zip',
        totalBytes: 10000,
        downloadedBytes: 2000,
        speedBytesPerSec: 2000.0,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(task.etaSeconds, 4); // (10000 - 2000) / 2000 = 4 seconds
    });

    test('serializes to and from JSON', () {
      final original = DownloadTask(
        id: 'task_123',
        url: 'https://example.com/archive.tar.gz',
        fileName: 'archive.tar.gz',
        savePath: '/data/downloads/archive.tar.gz',
        totalBytes: 52428800,
        downloadedBytes: 10485760,
        status: DownloadStatus.downloading,
        resumable: true,
        speedBytesPerSec: 1048576.0,
        errorMessage: null,
        createdAt: DateTime.parse('2026-11-02T12:00:00Z'),
        completedAt: null,
      );

      final json = original.toJson();
      final reconstructed = DownloadTask.fromJson(json);

      expect(reconstructed.id, original.id);
      expect(reconstructed.url, original.url);
      expect(reconstructed.fileName, original.fileName);
      expect(reconstructed.savePath, original.savePath);
      expect(reconstructed.totalBytes, original.totalBytes);
      expect(reconstructed.downloadedBytes, original.downloadedBytes);
      expect(reconstructed.status, original.status);
      expect(reconstructed.resumable, original.resumable);
      expect(reconstructed.speedBytesPerSec, original.speedBytesPerSec);
      expect(reconstructed.createdAt, original.createdAt);
    });

    test('copyWith produces modified copy without mutating original', () {
      final task = DownloadTask(
        id: '1',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        savePath: '/tmp/file.zip',
        status: DownloadStatus.queued,
        createdAt: DateTime(2026, 1, 1),
      );

      final updated = task.copyWith(
        status: DownloadStatus.completed,
        downloadedBytes: 1000,
        totalBytes: 1000,
      );

      expect(task.status, DownloadStatus.queued);
      expect(updated.status, DownloadStatus.completed);
      expect(updated.downloadedBytes, 1000);
      expect(updated.totalBytes, 1000);
      expect(updated.id, task.id);
    });
  });
}
