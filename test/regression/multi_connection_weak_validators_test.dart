import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/services/multi_connection_downloader.dart';
import '../support/test_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'CHARACTERIZATION: Multi-connection download on weak ETag server loops/resets forever instead of completing',
    timeout: const Timeout(Duration(seconds: 5)),
    () async {
      // Server supports Range (206) but only provides weak ETag: W/"netget-weak-v1"
      final server = NetGetTestServer(
        dataSize: 512 * 1024, // 512 KB
        validatorMode: ValidatorMode.weakEtag,
        rangeSupportMode: RangeSupportMode.supported,
      );
      await server.start();

      final tempDir = await Directory.systemTemp.createTemp('weak_etag_test_');
      final saveFile = File('${tempDir.path}/weak_etag_download.bin');

      try {
        final downloader = MultiConnectionDownloader(
          id: 'weak_etag_task',
          uri: server.downloadUri,
          savePath: saveFile.path,
          connectionCount: 2,
          clientFactory: () => HttpClient(),
        );

        // In buggy code: Segment 1 (startOffset > 0) has ifRangeValidator == null (because weak ETag is not strong),
        // throws _ServerResetToZeroException, catches it in start(), truncates file, and calls start() again recursively,
        // resulting in infinite reset loop or timeout!
        await downloader.start();

        // Expected in fixed engine: completes successfully and byte integrity matches server
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
