import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/services/multi_connection_downloader.dart';
import '../support/test_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'CHARACTERIZATION: Speed limiter has no effect in Dart engine; downloads complete at line rate without throttling',
    () async {
      // 1 MB test payload on unthrottled server
      final server = NetGetTestServer(
        dataSize: 1024 * 1024,
        validatorMode: ValidatorMode.strongEtag,
        rangeSupportMode: RangeSupportMode.supported,
      );
      await server.start();

      final tempDir = await Directory.systemTemp.createTemp(
        'speed_limit_test_',
      );
      final saveFile = File('${tempDir.path}/speed_test.bin');

      try {
        // SpeedMode.low is 256 KB/s (262,144 bytes/s).
        // A 1 MB payload throttled to 256 KB/s must take at least 3.0 seconds to transfer.
        final sw = Stopwatch()..start();

        final downloader = MultiConnectionDownloader(
          id: 'speed_limit_task',
          uri: server.downloadUri,
          savePath: saveFile.path,
          connectionCount: 1,
          clientFactory: () => HttpClient(),
        );

        await downloader.start();
        sw.stop();

        final elapsedSec = sw.elapsedMilliseconds / 1000.0;
        final throughputKBps = (1024 / (elapsedSec > 0 ? elapsedSec : 0.001));

        // In buggy engine: Dart downloader has no throttle mechanism, so it transfers at > 10,000 KB/s on loopback in < 200ms!
        // In fixed engine: Token-bucket speed limiter restricts throughput to <= 300 KB/s (takes >= 2.5s)
        expect(
          throughputKBps,
          lessThanOrEqualTo(350.0),
          reason:
              'Engine must throttle transfer rate when speed limit is active (was ${throughputKBps.toStringAsFixed(1)} KB/s in ${sw.elapsedMilliseconds}ms)',
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
