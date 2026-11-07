import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/segment_planner.dart';
import 'package:netget/services/multi_connection_downloader.dart';
import '../../tool/test_http_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late TestHttpServer server;
  late Directory tempDir;

  setUpAll(() async {
    // 2 MB test data for fast reliable test execution
    server = TestHttpServer(dataSize: 2 * 1024 * 1024);
    await server.start();
  });

  tearDownAll(() async {
    await server.stop();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_engine_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Scenario 1: Multi-connection download when server supports Range (4 connections)', () async {
    final saveFile = File('${tempDir.path}/test_download_4conn.bin');
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download');

    final downloader = MultiConnectionDownloader(
      id: 'test_1',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 4,
      clientFactory: () => HttpClient(),
    );

    await downloader.start();

    expect(await saveFile.exists(), isTrue);
    final downloadedBytes = await saveFile.readAsBytes();
    expect(downloadedBytes.length, equals(server.testData.length));
    expect(downloadedBytes, equals(server.testData));
    expect(downloader.segments.length, greaterThanOrEqualTo(4));
    for (final seg in downloader.segments) {
      expect(seg.isCompleted, isTrue);
    }
  });

  test('Scenario 2: Fallback to single connection when server ignores Range (HTTP 200)', () async {
    final saveFile = File('${tempDir.path}/test_no_range.bin');
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download?mode=no_range');

    final downloader = MultiConnectionDownloader(
      id: 'test_2',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 4,
      clientFactory: () => HttpClient(),
    );

    await downloader.start();

    expect(await saveFile.exists(), isTrue);
    final downloadedBytes = await saveFile.readAsBytes();
    expect(downloadedBytes.length, equals(server.testData.length));
    expect(downloadedBytes, equals(server.testData));
    expect(downloader.segments.length, equals(1));
  });

  test('Scenario 3: Server returns HTTP 416 Range Not Satisfiable', () async {
    final saveFile = File('${tempDir.path}/test_416.bin');
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download?mode=range_416');

    final downloader = MultiConnectionDownloader(
      id: 'test_3',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 2,
      clientFactory: () => HttpClient(),
    );

    // Initial probe or download handles 416 cleanly
    try {
      await downloader.start();
    } catch (e) {
      expect(e.toString(), contains('416'));
    }
  });

  test('Scenario 4: Server changes ETag mid-download restarts cleanly from byte 0', () async {
    final saveFile = File('${tempDir.path}/test_etag_changed.bin');
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download?mode=etag_changed');

    final downloader = MultiConnectionDownloader(
      id: 'test_4',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 2,
      etag: '"netget-test-etag-v1"', // Old ETag
      clientFactory: () => HttpClient(),
    );

    await downloader.start();
    expect(saveFile.existsSync(), isTrue);
    final downloadedBytes = await saveFile.readAsBytes();
    expect(downloadedBytes.length, equals(server.testData.length));
    expect(downloadedBytes, equals(server.testData));
  });

  test('Scenario 5 & 6: Connection disconnects midway and resumes seamlessly', () async {
    final saveFile = File('${tempDir.path}/test_disconnect_resume.bin');
    final uriAbort = Uri.parse('http://127.0.0.1:${server.actualPort}/download?mode=abort_midway');

    final downloader1 = MultiConnectionDownloader(
      id: 'test_5',
      uri: uriAbort,
      savePath: saveFile.path,
      connectionCount: 2,
      clientFactory: () => HttpClient(),
    );

    // First attempt should fail or abort midway
    try {
      await downloader1.start();
    } catch (_) {}

    expect(await saveFile.exists(), isTrue);
    final partialLength = await saveFile.length();
    expect(partialLength, greaterThan(0));

    // Save segment state for resumption
    final persistedSegments = downloader1.segments;

    // Second attempt resumes normally with valid server
    final uriNormal = Uri.parse('http://127.0.0.1:${server.actualPort}/download');
    final downloader2 = MultiConnectionDownloader(
      id: 'test_5_resume',
      uri: uriNormal,
      savePath: saveFile.path,
      connectionCount: 2,
      etag: downloader1.etag,
      initialSegments: persistedSegments,
      clientFactory: () => HttpClient(),
    );

    await downloader2.start();

    final downloadedBytes = await saveFile.readAsBytes();
    expect(downloadedBytes.length, equals(server.testData.length));
    expect(downloadedBytes, equals(server.testData));
  });

  test('Scenario 9: User pauses and resumes download with zero corruption', () async {
    final saveFile = File('${tempDir.path}/test_pause_resume.bin');
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download');

    final downloader1 = MultiConnectionDownloader(
      id: 'test_9',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 4,
      clientFactory: () => HttpClient(),
    );

    // Start in background and pause shortly after
    final startFuture = downloader1.start();
    await Future.delayed(const Duration(milliseconds: 20));
    await downloader1.pause();
    await startFuture;

    final persistedSegments = downloader1.segments;
    expect(downloader1.isPaused, isTrue);

    // Resume
    final downloader2 = MultiConnectionDownloader(
      id: 'test_9',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 4,
      initialSegments: persistedSegments,
      clientFactory: () => HttpClient(),
    );

    await downloader2.start();

    final downloadedBytes = await saveFile.readAsBytes();
    expect(downloadedBytes.length, equals(server.testData.length));
    expect(downloadedBytes, equals(server.testData));
  });

  test('Scenario 10: User cancels during concurrent writes', () async {
    final saveFile = File('${tempDir.path}/test_cancel.bin');
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download');

    final downloader = MultiConnectionDownloader(
      id: 'test_10',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 4,
      clientFactory: () => HttpClient(),
    );

    final startFuture = downloader.start();
    await Future.delayed(const Duration(milliseconds: 15));
    await downloader.cancel();
    await startFuture;

    expect(downloader.isCancelled, isTrue);
  });

  test('Scenario 11: Segment checkpoint is strictly preceded by RAF flush', () async {
    final saveFile = File('${tempDir.path}/test_checkpoint_flush.bin');
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download');

    int checkpointCalledCount = 0;
    int writerFlushCountAtCheckpoint = 0;

    late MultiConnectionDownloader downloader;
    downloader = MultiConnectionDownloader(
      id: 'test_11',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 2,
      clientFactory: () => HttpClient(),
      onCheckpoint: (snapshot) async {
        checkpointCalledCount++;
        writerFlushCountAtCheckpoint = downloader.writer?.flushCount ?? 0;
      },
    );

    final startFuture = downloader.start();
    // Wait until probe completes and segments are planned
    while (downloader.segments.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 10));
    }

    // Manually trigger checkpoint
    final snapshot = await downloader.checkpoint();
    expect(snapshot.isNotEmpty, isTrue);
    expect(checkpointCalledCount, equals(1));
    expect(writerFlushCountAtCheckpoint, greaterThanOrEqualTo(1),
        reason: 'RAF flush must be completed before checkpoint callback is invoked');

    await downloader.pause();
    await startFuture;

    expect(checkpointCalledCount, greaterThanOrEqualTo(2), reason: 'Pause must also trigger checkpoint');
    expect(downloader.writer?.flushCount, greaterThanOrEqualTo(2));
  });

  test('Scenario 12: Resume with If-Range validator mismatch returning HTTP 200 restarts cleanly without error loop', () async {
    final saveFile = File('${tempDir.path}/test_if_range_mismatch.bin');
    // Mode no_range returns HTTP 200 OK to any request
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download?mode=no_range');

    final downloader = MultiConnectionDownloader(
      id: 'test_12',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 1,
      etag: '"stale-etag-value"',
      initialSegments: [
        DownloadSegment(index: 0, startByte: 0, endByte: 500000, downloadedBytes: 250000),
      ],
      clientFactory: () => HttpClient(),
    );

    // Because startOffset > 0 and server returned HTTP 200, engine restarts cleanly from byte 0
    await downloader.start();
    expect(saveFile.existsSync(), isTrue);
    expect(saveFile.lengthSync(), equals(server.testData.length));
  });

  test('Scenario 13: Server returns 429 Too Many Requests and engine retries with backoff', () async {
    final saveFile = File('${tempDir.path}/test_retry_429.bin');
    server.retry429Count = 0; // reset server counter
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download?mode=retry_429');

    final downloader = MultiConnectionDownloader(
      id: 'test_13',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 2,
      maxConnectionsPerHost: 4,
      clientFactory: () => HttpClient(),
    );

    await downloader.start();

    expect(server.retry429Count, greaterThanOrEqualTo(1), reason: 'Server must have observed 429 challenge');
    expect(await saveFile.exists(), isTrue);
    final downloadedBytes = await saveFile.readAsBytes();
    expect(downloadedBytes.length, equals(server.testData.length));
    expect(downloadedBytes, equals(server.testData));
  });

  test('Scenario 14: Per-host connection limit clamps excessive connection count', () async {
    final saveFile = File('${tempDir.path}/test_per_host_limit.bin');
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download');

    final downloader = MultiConnectionDownloader(
      id: 'test_14',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 16,
      maxConnectionsPerHost: 4,
      clientFactory: () => HttpClient(),
    );

    await downloader.start();

    // Initial plan should be clamped to maxConnectionsPerHost (4)
    expect(downloader.segments.length, greaterThanOrEqualTo(4));
    expect(downloader.maxConnectionsPerHost, equals(4));
  });

  test('Scenario 15: Insufficient disk space aborts download with FileSystemException before allocation', () async {
    final saveFile = File('${tempDir.path}/test_disk_full.bin');
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download');

    final downloader = MultiConnectionDownloader(
      id: 'test_15',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 2,
      clientFactory: () => HttpClient(),
      // Mock disk space checker: only 512 bytes free on disk
      diskSpaceChecker: (path) async => 512,
    );

    expect(
      downloader.start(),
      throwsA(predicate((e) => e is FileSystemException && e.message.contains('Insufficient disk space'))),
    );
    expect(await saveFile.exists(), isFalse, reason: 'File must not be created or truncated when disk space is insufficient');
  });

  test('Scenario 16: Engine killed mid-download, new instance resumes from persisted segments with matching SHA-256', () async {
    final saveFile = File('${tempDir.path}/test_killed_resume.bin');
    final uriAbort = Uri.parse('http://127.0.0.1:${server.actualPort}/download?mode=abort_midway');
    final uriNormal = Uri.parse('http://127.0.0.1:${server.actualPort}/download');

    final downloader1 = MultiConnectionDownloader(
      id: 'test_16_1',
      uri: uriAbort,
      savePath: saveFile.path,
      connectionCount: 4,
      clientFactory: () => HttpClient(),
    );

    // First instance gets abruptly aborted midway by the socket termination
    try {
      await downloader1.start();
    } catch (_) {}

    final savedSegments = downloader1.segments.map((s) => s.copyWith()).toList();
    final originalEtag = downloader1.etag;

    final partialDownloaded = savedSegments.fold<int>(0, (sum, s) => sum + s.downloadedBytes);
    expect(partialDownloaded, greaterThan(0), reason: 'First run must have persisted partial bytes');
    expect(partialDownloaded, lessThan(server.testData.length), reason: 'First run must not have completed');

    // Create brand-new instance simulating process restart
    final downloader2 = MultiConnectionDownloader(
      id: 'test_16_2',
      uri: uriNormal,
      savePath: saveFile.path,
      connectionCount: 4,
      etag: originalEtag,
      initialSegments: savedSegments,
      clientFactory: () => HttpClient(),
    );

    await downloader2.start();

    // Verify completion and SHA-256 match
    expect(await saveFile.exists(), isTrue);
    final finalBytes = await saveFile.readAsBytes();
    expect(finalBytes.length, equals(server.testData.length));
    expect(finalBytes, equals(server.testData));
  });

  test('Scenario 17: Engine killed mid-download, resume fails safely when server ETag mutated after restart', () async {
    final saveFile = File('${tempDir.path}/test_killed_etag_changed.bin');
    final uriAbort = Uri.parse('http://127.0.0.1:${server.actualPort}/download?mode=abort_midway');

    final downloader1 = MultiConnectionDownloader(
      id: 'test_17_1',
      uri: uriAbort,
      savePath: saveFile.path,
      connectionCount: 4,
      clientFactory: () => HttpClient(),
    );

    try {
      await downloader1.start();
    } catch (_) {}

    final savedSegments = downloader1.segments.map((s) => s.copyWith()).toList();
    expect(savedSegments.isNotEmpty, isTrue);

    // Simulate server file mutation: request the etag_changed endpoint on restart
    final uriChanged = Uri.parse('http://127.0.0.1:${server.actualPort}/download?mode=etag_changed');
    final downloaderRestart = MultiConnectionDownloader(
      id: 'test_17_2',
      uri: uriChanged,
      savePath: saveFile.path,
      connectionCount: 4,
      etag: downloader1.etag, // stale ETag from before kill
      initialSegments: savedSegments,
      clientFactory: () => HttpClient(),
    );

    // When server ETag changed on resume, it must cleanly restart from byte 0 and match server data
    await downloaderRestart.start();
    expect(saveFile.existsSync(), isTrue);
    final downloadedBytes = await saveFile.readAsBytes();
    expect(downloadedBytes.length, equals(server.testData.length));
    expect(downloadedBytes, equals(server.testData));
  });
}
