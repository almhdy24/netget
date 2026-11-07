import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/services/multi_connection_downloader.dart';
import '../../tool/test_http_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late TestHttpServer server;
  late Directory tempDir;

  setUpAll(() async {
    server = TestHttpServer(dataSize: 1024 * 1024); // 1 MB
    await server.start();
  });

  tearDownAll(() async {
    await server.stop();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_limits_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Connection Limits: Retry-After is strictly capped at 60s', () async {
    final downloader = MultiConnectionDownloader(
      id: 'retry_after_test',
      uri: Uri.parse('http://127.0.0.1:${server.actualPort}/download'),
      savePath: '${tempDir.path}/retry_test.bin',
      clientFactory: () => HttpClient(),
    );

    // 1. Integer seconds exceeding 60s
    final delay120 = downloader.calculateRetryDelayForTesting(HttpStatus.tooManyRequests, '120', 0);
    expect(delay120, equals(const Duration(seconds: 60)), reason: '120s Retry-After must be capped at 60s');

    // 2. HTTP-Date 10 minutes in the future
    final futureDate = DateTime.now().add(const Duration(minutes: 10));
    final delayDate = downloader.calculateRetryDelayForTesting(
      HttpStatus.serviceUnavailable,
      HttpDate.format(futureDate),
      0,
    );
    expect(delayDate, equals(const Duration(seconds: 60)), reason: 'Future HTTP date >60s must be capped at 60s');

    // 3. Normal delay under 60s
    final delay15 = downloader.calculateRetryDelayForTesting(HttpStatus.tooManyRequests, '15', 0);
    expect(delay15, equals(const Duration(seconds: 15)));
  });

  test('Connection Limits: Global per-host limit clamps concurrent connections across multiple downloads', () async {
    final sharedPool = HostConnectionPool(maxConnectionsPerHost: 4);
    final host = '127.0.0.1';

    expect(sharedPool.availableSlots(host), equals(4));

    // Download 1 requests 3 connections
    final file1 = File('${tempDir.path}/dl1.bin');
    final dl1 = MultiConnectionDownloader(
      id: 'dl1',
      uri: Uri.parse('http://$host:${server.actualPort}/download'),
      savePath: file1.path,
      connectionCount: 3,
      hostPool: sharedPool,
      clientFactory: () => HttpClient(),
    );

    // Download 2 requests 3 connections to the same host
    final file2 = File('${tempDir.path}/dl2.bin');
    final dl2 = MultiConnectionDownloader(
      id: 'dl2',
      uri: Uri.parse('http://$host:${server.actualPort}/download'),
      savePath: file2.path,
      connectionCount: 3,
      hostPool: sharedPool,
      clientFactory: () => HttpClient(),
    );

    // Run both downloads concurrently
    await Future.wait([dl1.start(), dl2.start()]);

    expect(await file1.exists(), isTrue);
    expect(await file2.exists(), isTrue);
    expect(await file1.length(), equals(server.testData.length));
    expect(await file2.length(), equals(server.testData.length));

    // When all transfers finish, host pool active count must be 0
    expect(sharedPool.activeCount(host), equals(0));
    expect(sharedPool.availableSlots(host), equals(4));
  });
}
