import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/services/nearby_share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late Directory tempDir;
  late File sampleFile;
  late List<int> testData;
  late NearbyShareService shareService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_nearby_test_');
    sampleFile = File('${tempDir.path}/lecture.mp4');
    // Generate 128 KB of deterministic test bytes
    testData = List.generate(128 * 1024, (i) => (i * 7) % 256);
    await sampleFile.writeAsBytes(testData);
    shareService = NearbyShareService();
  });

  tearDown(() async {
    await shareService.stopSharing();
    shareService.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('NearbyShareService Tests (§5.3)', () {
    test('starts sharing and generates accessible local URL', () async {
      final url = await shareService.startSharing(
        sampleFile,
        customFileName: 'lecture.mp4',
        explicitIp: '127.0.0.1',
      );

      expect(shareService.isSharing, isTrue);
      expect(url, startsWith('http://127.0.0.1:'));
      expect(url, contains('/d/'));
      expect(url, endsWith('/lecture.mp4'));
    });

    test('full GET request downloads identical file bytes', () async {
      final url = await shareService.startSharing(
        sampleFile,
        customFileName: 'lecture.mp4',
        explicitIp: '127.0.0.1',
      );

      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();

        expect(response.statusCode, equals(HttpStatus.ok));
        expect(response.contentLength, equals(testData.length));
        expect(
          response.headers.value(HttpHeaders.acceptRangesHeader),
          equals('bytes'),
        );

        final receivedBytes = <int>[];
        await for (final chunk in response) {
          receivedBytes.addAll(chunk);
        }

        expect(receivedBytes, equals(testData));
        expect(shareService.transferredBytes, equals(testData.length));
      } finally {
        client.close(force: true);
      }
    });

    test('HTTP Range request returns 206 Partial Content', () async {
      final url = await shareService.startSharing(
        sampleFile,
        customFileName: 'lecture.mp4',
        explicitIp: '127.0.0.1',
      );

      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        // Request byte range 100 to 299 (200 bytes)
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=100-299');
        final response = await request.close();

        expect(response.statusCode, equals(HttpStatus.partialContent));
        expect(response.contentLength, equals(200));
        expect(
          response.headers.value(HttpHeaders.contentRangeHeader),
          equals('bytes 100-299/${testData.length}'),
        );

        final receivedBytes = <int>[];
        await for (final chunk in response) {
          receivedBytes.addAll(chunk);
        }

        expect(receivedBytes.length, equals(200));
        expect(receivedBytes, equals(testData.sublist(100, 300)));
      } finally {
        client.close(force: true);
      }
    });

    test('HEAD request returns file metadata without body', () async {
      final url = await shareService.startSharing(
        sampleFile,
        customFileName: 'lecture.mp4',
        explicitIp: '127.0.0.1',
      );

      final client = HttpClient();
      try {
        final request = await client.headUrl(Uri.parse(url));
        final response = await request.close();

        expect(response.statusCode, equals(HttpStatus.ok));
        expect(response.contentLength, equals(testData.length));
        expect(
          response.headers.value(HttpHeaders.acceptRangesHeader),
          equals('bytes'),
        );

        final bytes = await response.fold<List<int>>(
          [],
          (a, b) => a..addAll(b),
        );
        expect(bytes.isEmpty, isTrue);
      } finally {
        client.close(force: true);
      }
    });

    test('stopSharing immediately terminates server', () async {
      final url = await shareService.startSharing(
        sampleFile,
        customFileName: 'lecture.mp4',
        explicitIp: '127.0.0.1',
      );

      await shareService.stopSharing();
      expect(shareService.isSharing, isFalse);

      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        await request.close();
        fail('Should have failed to connect to stopped sharing server');
      } catch (e) {
        expect(e, isA<SocketException>());
      } finally {
        client.close(force: true);
      }
    });
  });
}
