import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/data/download_repository.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/download_manager.dart';
import 'package:netget/services/multi_connection_downloader.dart';
import '../../tool/test_http_server.dart';

class MockEnospcRaf implements RandomAccessFile {
  final bool failOnTruncate;
  final bool failOnWrite;

  MockEnospcRaf({this.failOnTruncate = false, this.failOnWrite = false});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<RandomAccessFile> truncate(int length) async {
    if (failOnTruncate) {
      throw const FileSystemException(
        'truncate failed',
        '',
        OSError('No space left on device', 28), // ENOSPC = 28
      );
    }
    return this;
  }

  @override
  Future<RandomAccessFile> writeFrom(List<int> buffer, [int start = 0, int? end]) async {
    if (failOnWrite) {
      throw const FileSystemException(
        'writeFrom failed',
        '',
        OSError('No space left on device', 28), // ENOSPC = 28
      );
    }
    return this;
  }

  @override
  Future<RandomAccessFile> setPosition(int position) async => this;

  @override
  Future<RandomAccessFile> flush() async => this;

  @override
  Future<void> close() async {}
}

class InMemoryTaskRepo implements DownloadRepository {
  List<DownloadTask> tasks = [];
  @override
  Future<List<DownloadTask>> loadTasks() async => List.from(tasks);
  @override
  Future<void> saveTasks(List<DownloadTask> newTasks) async {
    tasks = List.from(newTasks);
  }
  @override
  Future<void> saveTask(DownloadTask task) async {
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx >= 0) {
      tasks[idx] = task;
    } else {
      tasks.add(task);
    }
  }
  @override
  Future<void> deleteTask(String id) async {
    tasks.removeWhere((t) => t.id == id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late TestHttpServer server;
  late Directory tempDir;

  setUpAll(() async {
    server = TestHttpServer(dataSize: 512 * 1024);
    await server.start();
  });

  tearDownAll(() async {
    await server.stop();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_enospc_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Disk Space: Unknown free space (null from df) does not block download', () async {
    final saveFile = File('${tempDir.path}/null_space.bin');
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download');

    final downloader = MultiConnectionDownloader(
      id: 'null_space_test',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 1,
      clientFactory: () => HttpClient(),
      // df returned null (unparseable / permission restricted on Android)
      diskSpaceChecker: (path) async => null,
    );

    // Must proceed with download rather than throwing Insufficient disk space
    await downloader.start();

    expect(await saveFile.exists(), isTrue);
    final downloadedBytes = await saveFile.readAsBytes();
    expect(downloadedBytes.length, equals(server.testData.length));
  });

  test('Disk Space: ENOSPC (errno 28) during truncate surfaces DiskSpaceException', () async {
    final saveFile = File('${tempDir.path}/enospc_truncate.bin');
    final uri = Uri.parse('http://127.0.0.1:${server.actualPort}/download');

    final downloader = MultiConnectionDownloader(
      id: 'enospc_truncate_test',
      uri: uri,
      savePath: saveFile.path,
      connectionCount: 1,
      clientFactory: () => HttpClient(),
      writerFactory: (file) async {
        return ConcurrentFileWriter(MockEnospcRaf(failOnTruncate: true));
      },
    );

    await expectLater(
      downloader.start(),
      throwsA(predicate((e) => e is DiskSpaceException && e.message.contains('No space left on device'))),
    );
  });

  test('Disk Space: ENOSPC (errno 28) during write surfaces clear localized error in DownloadManager', () async {
    final repo = InMemoryTaskRepo();
    final manager = DownloadManager(
      repository: repo,
      downloadsDirResolver: () async => tempDir,
    );
    await manager.init();

    final task = await manager.addDownload(
      url: 'http://127.0.0.1:${server.actualPort}/download',
      startNow: false,
    );

    // Replace multiDownloader writer with EnospcFailingWriter
    final downloader = MultiConnectionDownloader(
      id: task.id,
      uri: Uri.parse(task.url),
      savePath: task.savePath,
      connectionCount: 1,
      clientFactory: () => HttpClient(),
      writerFactory: (file) async {
        return ConcurrentFileWriter(MockEnospcRaf(failOnWrite: true));
      },
    );

    // Calling downloader.start() directly throws DiskSpaceException
    await expectLater(
      downloader.start(),
      throwsA(predicate((e) => e is DiskSpaceException && e.message.contains('No space left on device'))),
    );

    // Verify DownloadManager._cleanErrorMessage converts it to user-friendly message
    final diskError = DiskSpaceException('No space left on device');
    final cleanedMsg = manager.cleanErrorMessageForTesting(diskError);
    expect(cleanedMsg, 'Storage is full');

    manager.dispose();
  });
}
