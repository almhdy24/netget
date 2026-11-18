import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/data/sqlite_download_repository.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/data_budget_service.dart';
import 'package:netget/services/download_manager.dart';
import 'package:netget/services/integrity_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockSidecarHttpClient implements HttpClient {
  final Map<String, String> responses;

  MockSidecarHttpClient(this.responses);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final urlStr = url.toString();
    final body = responses[urlStr];
    if (body != null) {
      return MockSidecarHttpRequest(statusCode: 200, body: body);
    }
    return MockSidecarHttpRequest(statusCode: 404, body: 'Not found');
  }

  @override
  void close({bool force = false}) {}
}

class MockSidecarHttpRequest implements HttpClientRequest {
  final int statusCode;
  final String body;

  MockSidecarHttpRequest({required this.statusCode, required this.body});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  final HttpHeaders headers = MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async {
    return MockSidecarHttpResponse(statusCode: statusCode, body: body);
  }
}

class MockSidecarHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;

  MockSidecarHttpResponse({required this.statusCode, required this.body});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final bytes = utf8.encode(body);
    return Stream<List<int>>.fromIterable([bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class MockHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late SqliteDownloadRepository repo;
  late DownloadManager manager;
  late IntegrityService integrityService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_integrity_test_');
    final dbPath = '${tempDir.path}/test.db';
    repo = SqliteDownloadRepository(customDbPath: dbPath);
    final db = await repo.database;
    final budgetService = DataBudgetService(
      dbResolver: () async => db,
      networkTypeResolver: () async => 'wifi',
    );
    integrityService = IntegrityService();
    manager = DownloadManager(
      repository: repo,
      budgetService: budgetService,
      integrityService: integrityService,
      downloadsDirResolver: () async => tempDir,
    );
    await manager.init();
  });

  tearDown(() async {
    manager.dispose();
    try {
      final db = await repo.database;
      if (db.isOpen) await db.close();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('IntegrityService & Checksums', () {
    test('computes SHA-256, SHA-1, and MD5 correctly on file', () async {
      const content = 'NetGet Resilient Engine Checksum Test 2026';
      final testFile = File('${tempDir.path}/test_hash.txt');
      await testFile.writeAsString(content);

      final expectedSha256 = sha256.convert(utf8.encode(content)).toString();
      final expectedSha1 = sha1.convert(utf8.encode(content)).toString();
      final expectedMd5 = md5.convert(utf8.encode(content)).toString();

      final actualSha256 = await integrityService.computeChecksum(
        filePath: testFile.path,
        algorithm: 'sha256',
      );
      final actualSha1 = await integrityService.computeChecksum(
        filePath: testFile.path,
        algorithm: 'sha1',
      );
      final actualMd5 = await integrityService.computeChecksum(
        filePath: testFile.path,
        algorithm: 'md5',
      );

      expect(actualSha256, equals(expectedSha256));
      expect(actualSha1, equals(expectedSha1));
      expect(actualMd5, equals(expectedMd5));
    });

    test('probes sidecar checksum file successfully', () async {
      const sha256Hash =
          'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f01234';
      final mockClient = MockSidecarHttpClient({
        'https://example.com/archive.zip.sha256': '$sha256Hash  archive.zip\n',
      });

      final service = IntegrityService(clientFactory: () => mockClient);
      final result = await service.probeSidecarChecksum(
        'https://example.com/archive.zip',
      );

      expect(result, isNotNull);
      expect(result!.algorithm, equals('sha256'));
      expect(result.checksum, equals(sha256Hash));
    });

    test(
      'DownloadTask isIntegrityVerified and hasChecksumMismatch properties',
      () {
        const hash1 = 'abc123def456';
        const hash2 = 'ABC123DEF456';
        const hash3 = '999999999999';

        var task = DownloadTask(
          id: 't1',
          url: 'https://example.com/f.zip',
          fileName: 'f.zip',
          savePath: '/tmp/f.zip',
          createdAt: DateTime.now(),
          checksumExpected: hash1,
          checksumActual: hash2,
        );
        expect(task.isIntegrityVerified, isTrue);
        expect(task.hasChecksumMismatch, isFalse);

        task = task.copyWith(checksumActual: hash3);
        expect(task.isIntegrityVerified, isFalse);
        expect(task.hasChecksumMismatch, isTrue);

        task = task.copyWith(clearChecksumExpected: true);
        expect(task.isIntegrityVerified, isFalse);
        expect(task.hasChecksumMismatch, isFalse);
      },
    );

    test('manual verifyTaskChecksum verifies and persists hashes', () async {
      const content = 'NetGet file integrity check content';
      final testFile = File('${tempDir.path}/sample.bin');
      await testFile.writeAsString(content);

      final expectedHash = sha256.convert(utf8.encode(content)).toString();

      final task = DownloadTask(
        id: 'task_manual_check',
        url: 'https://example.com/sample.bin',
        fileName: 'sample.bin',
        savePath: testFile.path,
        status: DownloadStatus.completed,
        createdAt: DateTime.now(),
      );
      await repo.saveTask(task);
      manager.updateTaskForTesting(task);

      final isMatch = await manager.verifyTaskChecksum(
        task.id,
        expectedHash: expectedHash,
        algorithm: 'sha256',
      );

      expect(isMatch, isTrue);
      final updated = manager.getTask(task.id)!;
      expect(updated.checksumActual, equals(expectedHash));
      expect(updated.checksumExpected, equals(expectedHash));
      expect(updated.isIntegrityVerified, isTrue);
    });
  });

  group('Honest Insights & Resilience Metrics', () {
    test(
      'tracks bytesPreservedByResume and interruptionsRecovered on resume',
      () async {
        final task = DownloadTask(
          id: 'task_resilience',
          url: 'https://example.com/movie.mkv',
          fileName: 'movie.mkv',
          savePath: '${tempDir.path}/movie.mkv',
          totalBytes: 10000000,
          downloadedBytes: 4000000,
          status: DownloadStatus.failed,
          errorMessage: 'Network connection lost',
          createdAt: DateTime.now(),
          interruptionsRecovered: 1,
          bytesPreservedByResume: 4000000,
        );
        await repo.saveTask(task);
        manager.updateTaskForTesting(task);

        // Resuming the failed task increments interruptionsRecovered
        await manager.resumeDownload(task.id);

        final resumed = manager.getTask(task.id)!;
        expect(
          resumed.status,
          anyOf(DownloadStatus.queued, DownloadStatus.downloading),
        );
        expect(resumed.interruptionsRecovered, equals(2));
        expect(resumed.bytesPreservedByResume, equals(4000000));
      },
    );
  });
}
