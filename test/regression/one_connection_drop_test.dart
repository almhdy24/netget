import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/services/multi_connection_downloader.dart';
import '../support/test_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'CHARACTERIZATION: One connection drop mid-segment aborts or restarts from byte 0 instead of resuming segment',
    () async {
      // 512 KB payload, drop connection after 50 KB on segment 1 (startByte > 0)
      final server = NetGetTestServer(
        dataSize: 512 * 1024,
        validatorMode: ValidatorMode.strongEtag,
        rangeSupportMode: RangeSupportMode.supported,
        dropAfterBytes: 50 * 1024,
        dropOnlyForOffset: 256 * 1024, // drop only segment 1
      );
      await server.start();

      final tempDir = await Directory.systemTemp.createTemp('conn_drop_test_');
      final saveFile = File('${tempDir.path}/conn_drop_download.bin');

      try {
        final downloader = MultiConnectionDownloader(
          id: 'conn_drop_task',
          uri: server.downloadUri,
          savePath: saveFile.path,
          connectionCount: 2,
          clientFactory: () => HttpClient(),
        );

        // In buggy engine: when segment 1 drops mid-transfer, _runSegmentWorker rethrows,
        // Future.wait fails immediately, and start() throws SocketException / HttpException
        // rather than retrying segment 1 with backoff!
        await downloader.start();

        // In fixed engine: segment 1 retries automatically from its current offset and file completes with full integrity
        expect(await saveFile.exists(), isTrue);
        final bytes = await saveFile.readAsBytes();
        expect(bytes.length, equals(server.data.length));
        expect(bytes, equals(server.data));
      } finally {
        await server.stop();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );
}
