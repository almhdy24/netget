import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/segment_planner.dart';
import 'package:netget/services/multi_connection_downloader.dart';
import '../support/test_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'CHARACTERIZATION: Free-space check on resume requires totalBytes instead of remaining bytes (totalBytes - alreadyDownloaded)',
    () async {
      const totalSize = 1000 * 1024; // 1000 KB total
      const alreadyDownloaded = 800 * 1024; // 800 KB already on disk
      const freeDiskSpace =
          400 *
          1024; // 400 KB available disk space (plenty for the remaining 200 KB!)

      final server = NetGetTestServer(
        dataSize: totalSize,
        validatorMode: ValidatorMode.strongEtag,
        rangeSupportMode: RangeSupportMode.supported,
      );
      await server.start();

      final tempDir = await Directory.systemTemp.createTemp('free_space_test_');
      final saveFile = File('${tempDir.path}/free_space_resume.bin');

      try {
        final downloader = MultiConnectionDownloader(
          id: 'free_space_task',
          uri: server.downloadUri,
          savePath: saveFile.path,
          connectionCount: 1,
          diskSpaceChecker: (_) async => freeDiskSpace,
          initialSegments: const [
            DownloadSegment(
              index: 0,
              startByte: 0,
              endByte: totalSize - 1,
              downloadedBytes: alreadyDownloaded,
            ),
          ],
          clientFactory: () => HttpClient(),
        );

        // In buggy engine:
        // Line 477 checks `freeBytes < totalBytes` (400 KB < 1000 KB) and throws:
        // `FileSystemException: Insufficient disk space: need 1024000 bytes, but only 409600 bytes available`!
        // Even though only 200 KB is needed to finish!
        // In fixed engine: required space = totalBytes - alreadyDownloaded (200 KB), which fits in 400 KB!
        await downloader.start();

        expect(await saveFile.exists(), isTrue);
      } finally {
        await server.stop();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );
}
