import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/segment_planner.dart';
import 'package:netget/services/multi_connection_downloader.dart';
import '../../tool/test_http_server.dart';

/// Test writer that simulates a disk failure after writing a limited number of bytes.
class FailingConcurrentFileWriter extends ConcurrentFileWriter {
  final int maxBytesBeforeFailure;
  int _totalWritten = 0;
  bool _failed = false;

  FailingConcurrentFileWriter(super.raf, {required this.maxBytesBeforeFailure});

  @override
  Future<void> writeAt(int offset, List<int> bytes) {
    if (_failed || _totalWritten + bytes.length > maxBytesBeforeFailure) {
      _failed = true;
      return Future.error(
        const FileSystemException('I/O error: disk write failure midway', ''),
      );
    }
    _totalWritten += bytes.length;
    return super.writeAt(offset, bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late TestHttpServer server;
  late Directory tempDir;

  setUpAll(() async {
    // 2 MB server test data
    server = TestHttpServer(dataSize: 2 * 1024 * 1024);
    await server.start();
  });

  tearDownAll(() async {
    await server.stop();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_checkpoint_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Checkpoint: onCheckpoint is invoked during normal progress without calling pause()', () async {
    final saveFile = File('${tempDir.path}/normal_progress_checkpoint.bin');
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download');

    final checkpointSnapshots = <List<DownloadSegment>>[];

    final downloader = MultiConnectionDownloader(
      id: 'checkpoint_normal_test',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 2,
      clientFactory: () => HttpClient(),
      onCheckpoint: (segs) async {
        checkpointSnapshots.add(segs.map((s) => s.copyWith()).toList());
      },
    );

    await downloader.start();

    // Verify onCheckpoint was invoked at least once (e.g. final completion checkpoint)
    expect(checkpointSnapshots.isNotEmpty, isTrue, reason: 'onCheckpoint must be invoked during normal execution flow');

    // Verify the final checkpoint snapshot matches total size
    final finalSnapshot = checkpointSnapshots.last;
    final totalBytesCheckpoint = finalSnapshot.fold<int>(0, (sum, s) => sum + s.downloadedBytes);
    expect(totalBytesCheckpoint, equals(server.testData.length));
    expect(finalSnapshot.every((s) => s.isFinished && s.isCompleted), isTrue);

    final fileBytes = await saveFile.readAsBytes();
    expect(fileBytes, equals(server.testData));
  });

  test('Checkpoint: Persisted offset never exceeds bytes written+flushed when writer fails midway', () async {
    final saveFile = File('${tempDir.path}/failing_writer_checkpoint.bin');
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download');

    const maxAllowedBytes = 128 * 1024; // 128 KB allowed before failure
    final checkpointSnapshots = <List<DownloadSegment>>[];

    final downloader = MultiConnectionDownloader(
      id: 'checkpoint_fail_test',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 1, // Single connection to test deterministic byte count
      clientFactory: () => HttpClient(),
      writerFactory: (file) async {
        final raf = await file.open(mode: FileMode.append);
        return FailingConcurrentFileWriter(raf, maxBytesBeforeFailure: maxAllowedBytes);
      },
      onCheckpoint: (segs) async {
        checkpointSnapshots.add(segs.map((s) => s.copyWith()).toList());
      },
    );

    // Engine must throw FileSystemException
    expect(
      downloader.start(),
      throwsA(predicate((e) => e is FileSystemException && e.message.contains('disk write failure'))),
    );

    // Wait microtask tick for all async handlers
    await Future.delayed(const Duration(milliseconds: 100));

    // For every recorded checkpoint, verify that the total recorded bytes never exceeds maxAllowedBytes
    for (final snapshot in checkpointSnapshots) {
      final totalRecorded = snapshot.fold<int>(0, (sum, s) => sum + s.downloadedBytes);
      expect(
        totalRecorded,
        lessThanOrEqualTo(maxAllowedBytes),
        reason: 'Persisted checkpoint offset ($totalRecorded) must never exceed bytes written+flushed ($maxAllowedBytes)',
      );
    }

    // Verify segments in downloader itself do not count the failed write
    final currentTotal = downloader.segments.fold<int>(0, (sum, s) => sum + s.downloadedBytes);
    expect(
      currentTotal,
      lessThanOrEqualTo(maxAllowedBytes),
      reason: 'Downloader segments must never increment offset when writeAt fails',
    );
  });
}
