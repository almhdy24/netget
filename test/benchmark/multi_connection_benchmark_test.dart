import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/services/multi_connection_downloader.dart';
import '../../tool/test_http_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('Benchmark: Throughput, Memory, and Integrity across 1, 2, 4, and 8 connections', () async {
    const testFileSize = 10 * 1024 * 1024; // 10 MB
    final server = TestHttpServer(dataSize: testFileSize);
    await server.start();

    final tempDir = await Directory.systemTemp.createTemp('netget_benchmark_');
    final connectionLevels = [1, 2, 4, 8];
    final results = <Map<String, dynamic>>[];

    try {
      for (final connCount in connectionLevels) {
        final saveFile = File('${tempDir.path}/bench_${connCount}conn.bin');
        final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download');

        final downloader = MultiConnectionDownloader(
          id: 'bench_$connCount',
          uri: uri,
          savePath: saveFile.path,
          connectionCount: connCount,
          clientFactory: () => HttpClient(),
        );

        final memBefore = ProcessInfo.currentRss;
        final stopwatch = Stopwatch()..start();

        await downloader.start();

        stopwatch.stop();
        final memAfter = ProcessInfo.currentRss;

        final elapsedMs = stopwatch.elapsedMilliseconds;
        final elapsedSec = elapsedMs / 1000.0;
        final throughputMBps = (testFileSize / (1024 * 1024)) / (elapsedSec > 0 ? elapsedSec : 0.001);

        // Verify file integrity
        final downloadedBytes = await saveFile.readAsBytes();
        bool isMatch = (downloadedBytes.length == server.testData.length);
        if (isMatch) {
          for (int i = 0; i < downloadedBytes.length; i++) {
            if (downloadedBytes[i] != server.testData[i]) {
              isMatch = false;
              break;
            }
          }
        }

        final result = {
          'connections': connCount,
          'timeMs': elapsedMs,
          'timeSec': elapsedSec,
          'throughputMBps': throughputMBps,
          'memDeltaKB': (memAfter - memBefore) ~/ 1024,
          'verifiedIntegrity': isMatch,
          'segments': downloader.segments.length,
        };
        results.add(result);

        expect(isMatch, isTrue, reason: 'Downloaded file must match server test data 100%');
        await saveFile.delete();
      }

      print('\n==================== BENCHMARK SUMMARY (10 MB Payload) ====================');
      print('| Connections | Time (ms) | Throughput (MB/s) | Segments | Memory Δ | Integrity |');
      print('|:-----------:|:---------:|:-----------------:|:--------:|:--------:|:---------:|');
      for (final r in results) {
        print('| ${r['connections'].toString().padLeft(11)} | ${r['timeMs'].toString().padLeft(9)} | ${r['throughputMBps'].toStringAsFixed(2).padLeft(17)} | ${r['segments'].toString().padLeft(8)} | ${(r['memDeltaKB'].toString() + " KB").padLeft(8)} | ${r['verifiedIntegrity'] ? "PASS (0 bit err)" : "FAIL"} |');
      }
      print('===========================================================================\n');
    } finally {
      await server.stop();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}
