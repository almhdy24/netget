// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings
import 'dart:io';
import 'package:netget/services/multi_connection_downloader.dart';
import 'test_http_server.dart';

Future<void> main() async {
  print('===============================================================');
  print('          NETGET MULTI-CONNECTION PERFORMANCE BENCHMARK        ');
  print('===============================================================');

  const testFileSize = 10 * 1024 * 1024; // 10 MB
  final server = TestHttpServer(dataSize: testFileSize);
  await server.start();
  print('HTTP Server running on port ${server.actualPort} (Payload: 10.00 MB)');

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
      final throughputMBps =
          (testFileSize / (1024 * 1024)) /
          (elapsedSec > 0 ? elapsedSec : 0.001);

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

      print(
        '[$connCount conn] ${elapsedMs}ms | ${throughputMBps.toStringAsFixed(2)} MB/s | Mem delta: ${result['memDeltaKB']} KB | Integrity: ${isMatch ? "VERIFIED (100% SHA match)" : "CORRUPTED"}',
      );
      await saveFile.delete();
    }

    print('\n==================== BENCHMARK SUMMARY ====================');
    print(
      '| Connections | Time (ms) | Throughput (MB/s) | Segments | Memory Δ | Integrity |',
    );
    print(
      '|:-----------:|:---------:|:-----------------:|:--------:|:--------:|:---------:|',
    );
    for (final r in results) {
      final verified = r['verifiedIntegrity'] == true;
      final throughput = (r['throughputMBps'] as num).toDouble();
      print(
        '| ${r['connections'].toString().padLeft(11)} | ${r['timeMs'].toString().padLeft(9)} | ${throughput.toStringAsFixed(2).padLeft(17)} | ${r['segments'].toString().padLeft(8)} | ${(r['memDeltaKB'].toString() + " KB").padLeft(8)} | ${verified ? "PASS (0 bit err)" : "FAIL"} |',
      );
    }
    print('===========================================================\n');
  } finally {
    await server.stop();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}
