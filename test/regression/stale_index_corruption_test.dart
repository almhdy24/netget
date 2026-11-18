import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/download_manager.dart';
import 'package:netget/data/download_repository.dart';

class InMemoryDownloadRepo implements DownloadRepository {
  List<DownloadTask> tasks = [];
  @override
  Future<List<DownloadTask>> loadTasks() async => List.from(tasks);
  @override
  Future<void> saveTasks(List<DownloadTask> list) async {
    tasks = List.from(list);
  }

  @override
  Future<void> saveTask(DownloadTask task) async {
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx >= 0) {
      tasks[idx] = task;
    } else {
      tasks.insert(0, task);
    }
  }

  @override
  Future<void> deleteTask(String id) async {
    tasks.removeWhere((t) => t.id == id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CHARACTERIZATION: Adding a task while another is connecting corrupts tasks due to captured index',
    () async {
      final repo = InMemoryDownloadRepo();
      final tempDir = await Directory.systemTemp.createTemp('stale_index_test');
      final connectingCompleter = Completer<void>();
      final allowResponseCompleter = Completer<void>();

      final manager = DownloadManager(
        repository: repo,
        downloadsDirResolver: () async => tempDir,
        clientFactory: () {
          return _ControlledHttpClient(
            onClose: () async {
              if (!connectingCompleter.isCompleted) {
                connectingCompleter.complete();
              }
              await allowResponseCompleter.future;
              return _ControlledHttpResponse();
            },
          );
        },
      );
      await manager.init();

      try {
        // Add Task A, startNow = true -> enters _startDownloading, index = 0 captured
        final taskA = await manager.addDownload(
          url: 'http://example.com/fileA.zip',
          startNow: true,
        );

        // Wait until Task A has sent request and is awaiting response
        await connectingCompleter.future;

        // Add Task B while Task A is waiting for response -> inserted at index 0!
        // Now _tasks[0] is Task B and _tasks[1] is Task A.
        final taskB = await manager.addDownload(
          url: 'http://example.com/fileB.zip',
          startNow: false,
        );

        // Unblock Task A response. Task A will write to its captured index 0!
        allowResponseCompleter.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // In buggy code: Task A overwrote Task B at index 0 because index was captured!
        expect(
          manager.tasks[0].id,
          equals(taskB.id),
          reason:
              'Task B must remain at index 0 and not be overwritten by Task A',
        );
        expect(
          manager.tasks[1].id,
          equals(taskA.id),
          reason: 'Task A should be at index 1',
        );
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );
}

class _ControlledHttpClient implements HttpClient {
  final Future<HttpClientResponse> Function() onClose;
  _ControlledHttpClient({required this.onClose});

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getUrl || invocation.memberName == #openUrl) {
      return Future.value(_ControlledHttpRequest(onClose: onClose));
    }
    if (invocation.memberName == #close) {
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

class _ControlledHttpRequest implements HttpClientRequest {
  final Future<HttpClientResponse> Function() onClose;
  _ControlledHttpRequest({required this.onClose});

  final HttpHeaders _headers = _MockHeaders();
  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() => onClose();

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final StreamController<List<int>> _controller = StreamController<List<int>>();

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => 1024;

  @override
  HttpHeaders get headers => _MockHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHeaders implements HttpHeaders {
  final Map<String, dynamic> _map = {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _map[name.toLowerCase()] = value;
  }

  @override
  String? value(String name) => _map[name.toLowerCase()]?.toString();
}
