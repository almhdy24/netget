import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/constants.dart';
import 'package:netget/services/storage_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory mockExternalDir;
  late Directory mockPublicDir;
  late StorageService storageService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('storage_service_test_');
    mockExternalDir = Directory(p.join(tempDir.path, 'mock_external'));
    mockPublicDir = Directory(p.join(tempDir.path, 'mock_public'));
    await mockExternalDir.create(recursive: true);
    await mockPublicDir.create(recursive: true);

    storageService = StorageService(
      externalFilesResolver: () async => mockExternalDir,
      publicDownloadsResolver: () async => mockPublicDir,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'StorageService resolves part file path under parts directory',
    () async {
      final partPath = await storageService.getPartFilePath('task_123');
      expect(partPath, endsWith('parts/task_123.part'));
      expect(await File(partPath).parent.exists(), isTrue);
    },
  );

  test(
    'StorageService resolves collision-free target path in public category directory',
    () async {
      final target1 = await storageService.resolveTargetFilePath(
        fileName: 'video.mp4',
        category: DownloadCategory.video,
      );
      expect(target1, contains('NetGet/Video/video.mp4'));

      // Create file at target1 to simulate existing file
      final f1 = File(target1);
      await f1.parent.create(recursive: true);
      await f1.writeAsString('existing content');

      // Second resolution must avoid collision with (1)
      final target2 = await storageService.resolveTargetFilePath(
        fileName: 'video.mp4',
        category: DownloadCategory.video,
      );
      expect(target2, contains('NetGet/Video/video(1).mp4'));
    },
  );

  test(
    'StorageService finalizes download: moves .part, verifies size, and cleans up .part',
    () async {
      final partPath = await storageService.getPartFilePath('task_finalize');
      final partFile = File(partPath);
      final data = List.generate(5000, (i) => i % 256);
      await partFile.writeAsBytes(data, flush: true);

      final targetPath = p.join(mockPublicDir.path, 'finished.bin');

      double lastProgress = 0.0;
      final finalizedPath = await storageService.finalizeDownload(
        partFilePath: partPath,
        targetFilePath: targetPath,
        expectedBytes: 5000,
        onProgress: (prog) => lastProgress = prog,
      );

      expect(finalizedPath, equals(targetPath));
      expect(lastProgress, equals(1.0));

      final targetFile = File(targetPath);
      expect(await targetFile.exists(), isTrue);
      expect(await targetFile.length(), equals(5000));

      // Temporary .part file must be removed after successful finalization
      expect(await partFile.exists(), isFalse);
    },
  );

  test(
    'StorageService finalization throws and preserves .part when size does not match expected',
    () async {
      final partPath = await storageService.getPartFilePath('task_corrupt');
      final partFile = File(partPath);
      // Write only 100 bytes while 500 are expected
      await partFile.writeAsBytes(List.generate(100, (i) => i), flush: true);

      final targetPath = p.join(mockPublicDir.path, 'corrupt.bin');

      expect(
        () => storageService.finalizeDownload(
          partFilePath: partPath,
          targetFilePath: targetPath,
          expectedBytes: 500,
        ),
        throwsA(isA<FileSystemException>()),
      );

      // .part file must be preserved so download is not lost
      expect(await partFile.exists(), isTrue);
    },
  );
}
