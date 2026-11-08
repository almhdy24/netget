// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/services/multi_connection_downloader.dart';
import '../../tool/test_http_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'Benchmark: Throughput, Memory, and Integrity across 1, 2, 4, and 8 connections',
    () async {
      const testFileSize = 10 * 1024 * 1024; // 10 MB
      final server = TestHttpServer(dataSize: testFileSize);
      await server.start();

      final tempDir = await Directory.systemTemp.createTemp(
        'netget_benchmark_',
      );
      final connectionLevels = [1, 2, 4, 8];
      final results = <Map<String, dynamic>>[];

      try {
        for (final connCount in connectionLevels) {
          final saveFile = File('${tempDir.path}/bench_${connCount}conn.bin');
          final uri = Uri.parse(
            'http://127.0.0.1:${server.actualPort}/download',
          );

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

          expect(
            isMatch,
            isTrue,
            reason: 'Downloaded file must match server test data 100%',
          );
          await saveFile.delete();
        }

        print(
          '\n==================== BENCHMARK SUMMARY (10 MB Payload) ====================',
        );
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
        print(
          '===========================================================================\n',
        );
      } finally {
        await server.stop();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

  test(
    'Benchmark: Throttled server (1 MB/s per connection) across 1, 2, 4, 8 connections (3 runs each, median)',
    () async {
      const fileSize = 3 * 1024 * 1024; // 3 MB
      final server = TestHttpServer(
        dataSize: fileSize,
        throttleBytesPerSec: 1024 * 1024, // 1 MB/s per connection
      );
      await server.start();

      final tempDir = await Directory.systemTemp.createTemp(
        'netget_throttled_bench_',
      );
      final connectionLevels = [1, 2, 4, 8];
      final summary = <Map<String, dynamic>>[];

      try {
        for (final connCount in connectionLevels) {
          final runTimesMs = <int>[];
          int actualConnections = connCount;

          for (int run = 1; run <= 3; run++) {
            final saveFile = File(
              '${tempDir.path}/throttled_${connCount}conn_run$run.bin',
            );
            final uri = Uri.parse(
              'http://127.0.0.1:${server.actualPort}/download',
            );

            final downloader = MultiConnectionDownloader(
              id: 'throttled_${connCount}_$run',
              uri: uri,
              savePath: saveFile.path,
              connectionCount: connCount,
              maxConnectionsPerHost: 8,
              hostPool: HostConnectionPool(maxConnectionsPerHost: 8),
              clientFactory: () => HttpClient(),
            );

            final sw = Stopwatch()..start();
            await downloader.start();
            sw.stop();
            runTimesMs.add(sw.elapsedMilliseconds);
            actualConnections = downloader.segments.length;

            final bytes = await saveFile.readAsBytes();
            expect(bytes.length, equals(server.testData.length));
            expect(bytes, equals(server.testData));
            await saveFile.delete();
          }

          // Compute median
          runTimesMs.sort();
          final medianMs = runTimesMs[1]; // middle of 3
          final medianSec = medianMs / 1000.0;
          final medianThroughputMBps =
              (fileSize / (1024 * 1024)) / (medianSec > 0 ? medianSec : 0.001);

          summary.add({
            'requested': connCount,
            'actual': actualConnections,
            'runsMs': runTimesMs,
            'medianMs': medianMs,
            'medianSec': medianSec,
            'medianThroughputMBps': medianThroughputMBps,
          });
        }

        final payloadMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);
        print(
          '\n================ THROTTLED SERVER BENCHMARK (1 MB/s per socket, 3 runs each) ================',
        );
        print('REAL PAYLOAD SIZE: $payloadMB MB ($fileSize bytes)');
        print(
          'NOTICE: Loopback results are non-representative of real-world internet links because loopback',
        );
        print(
          'exhibits near-zero latency and high context-switching overhead. This benchmark simulates real',
        );
        print(
          'rate-limited CDNs that cap each individual TCP connection to 1 MB/s.',
        );
        print(
          '---------------------------------------------------------------------------------------------------------',
        );
        print(
          '| Requested | Actual Used | Runs (ms)            | Median Time (ms) | Median Throughput | Scaling Factor |',
        );
        print(
          '|:---------:|:-----------:|:--------------------:|:----------------:|:-----------------:|:--------------:|',
        );
        final baseTime = summary.first['medianMs'] as int;
        for (final s in summary) {
          final scaling =
              (baseTime / (s['medianMs'] as int)).toStringAsFixed(2) + 'x';
          final runsStr = (s['runsMs'] as List<int>).join(', ');
          print(
            '| ${s['requested'].toString().padLeft(9)} | ${s['actual'].toString().padLeft(11)} | ${runsStr.padRight(20)} | ${s['medianMs'].toString().padLeft(16)} | ${(s['medianThroughputMBps'] as double).toStringAsFixed(2) + " MB/s"} | ${scaling.padLeft(14)} |',
          );
        }
        print(
          '=========================================================================================================\n',
        );
      } finally {
        await server.stop();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );
}
