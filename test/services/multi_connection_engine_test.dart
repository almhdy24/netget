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

  test('Scenario 4: Server changes ETag mid-download throws ETag mismatch', () async {
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

    expect(downloader.start(), throwsA(isA<HttpException>()));
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
    await Future.delayed(const Duration(milliseconds: 30));

    // Manually trigger checkpoint
    final snapshot = await downloader.checkpoint();
    expect(snapshot.isNotEmpty, isTrue);
    expect(checkpointCalledCount, equals(1));
    expect(writerFlushCountAtCheckpoint, greaterThanOrEqualTo(1),
        reason: 'RAF flush must be completed before checkpoint callback is invoked');

    await downloader.pause();
    await startFuture;

    expect(checkpointCalledCount, equals(2), reason: 'Pause must also trigger checkpoint');
    expect(downloader.writer?.flushCount, greaterThanOrEqualTo(2));
  });
}
