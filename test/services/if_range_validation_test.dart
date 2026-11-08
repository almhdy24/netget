import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/segment_planner.dart';
import 'package:netget/core/utils.dart';
import 'package:netget/services/multi_connection_downloader.dart';
import '../../tool/test_http_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_ifrange_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('If-Range: Strong vs Weak ETag validation rules', () {
    expect(NetGetUtils.isStrongEtag('"strong-etag-123"'), isTrue);
    expect(NetGetUtils.isStrongEtag('W/"weak-etag-456"'), isFalse);
    expect(NetGetUtils.isStrongEtag('w/"weak-etag-789"'), isFalse);
    expect(NetGetUtils.isStrongEtag(null), isFalse);
    expect(NetGetUtils.isStrongEtag(''), isFalse);
    expect(NetGetUtils.isStrongEtag('   '), isFalse);
  });

  test(
    'If-Range: Weak ETag without Last-Modified does not resume, restarts cleanly from byte 0',
    () async {
      final server = TestHttpServer(dataSize: 512 * 1024);
      await server.start();

      final saveFile = File('${tempDir.path}/weak_etag.bin');
      final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download');

      final initialSegments = const [
        DownloadSegment(
          index: 0,
          startByte: 0,
          endByte: (512 * 1024) - 1,
          downloadedBytes: 100 * 1024,
        ),
      ];

      final downloader = MultiConnectionDownloader(
        id: 'weak_etag_test',
        uri: uri,
        savePath: saveFile.path,
        connectionCount: 1,
        clientFactory: () => HttpClient(),
        etag: 'W/"weak-etag"', // Weak validator
        lastModified: null, // No fallback
        initialSegments: initialSegments,
      );

      // Engine must restart cleanly from 0 rather than failing
      await downloader.start();

      expect(await saveFile.exists(), isTrue);
      final downloadedBytes = await saveFile.readAsBytes();
      expect(downloadedBytes.length, equals(server.testData.length));
      expect(downloadedBytes, equals(server.testData));

      await server.stop();
    },
  );

  test(
    'If-Range: Server answering with 200 OK restarts cleanly from byte 0 without error loop',
    () async {
      final server = TestHttpServer(dataSize: 512 * 1024);
      await server.start();

      final saveFile = File('${tempDir.path}/if_range_200.bin');
      // Request no_range mode to return 200 OK for range requests
      final uri = Uri.parse(
        'http://127.0.0.1:${server.actualPort}/download?mode=no_range',
      );

      final initialSegments = const [
        DownloadSegment(
          index: 0,
          startByte: 0,
          endByte: (512 * 1024) - 1,
          downloadedBytes: 256 * 1024,
        ),
      ];

      final downloader = MultiConnectionDownloader(
        id: 'if_range_200_test',
        uri: uri,
        savePath: saveFile.path,
        connectionCount: 1,
        clientFactory: () => HttpClient(),
        etag: '"valid-strong-etag"',
        initialSegments: initialSegments,
      );

      // Must restart from byte 0 cleanly and succeed
      await downloader.start();

      expect(await saveFile.exists(), isTrue);
      final downloadedBytes = await saveFile.readAsBytes();
      expect(downloadedBytes.length, equals(server.testData.length));
      expect(downloadedBytes, equals(server.testData));

      await server.stop();
    },
  );

  test(
    'If-Range: Server returning unexpected Content-Range start throws HttpException',
    () async {
      // Custom mock server returning mismatched Content-Range start
      final mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockServer.listen((req) async {
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        req.response.headers.set(HttpHeaders.etagHeader, '"test-etag"');
        // Client requested start 0 or 100, server responds with invalid start 5000
        req.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 5000-6000/10000',
        );
        req.response.headers.contentLength = 1001;
        req.response.add(List.filled(1001, 1));
        await req.response.close();
      });

      final saveFile = File('${tempDir.path}/mismatched_range.bin');
      final uri = Uri.parse('http://127.0.0.1:${mockServer.port}/download');

      final downloader = MultiConnectionDownloader(
        id: 'mismatched_content_range_test',
        uri: uri,
        savePath: saveFile.path,
        connectionCount: 1,
        clientFactory: () => HttpClient(),
        etag: '"test-etag"',
      );

      await expectLater(
        downloader.start(),
        throwsA(
          predicate(
            (e) =>
                e is HttpException &&
                e.message.contains('unexpected Content-Range start'),
          ),
        ),
      );

      await mockServer.close(force: true);
    },
  );
}
