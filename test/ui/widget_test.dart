import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/data/download_repository.dart';
import 'package:netget/main.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/download_manager.dart';
import 'package:netget/ui/widgets/download_card.dart';

class TestDownloadRepository implements DownloadRepository {
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

class DummyHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => DummyHttpRequest();

  @override
  void close({bool force = false}) {}
}

class DummyHttpRequest implements HttpClientRequest {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final HttpHeaders _headers = DummyHttpHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() => Completer<HttpClientResponse>().future;
}

class DummyHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('NetGetApp renders home dashboard, empty state, and controls', (
    WidgetTester tester,
  ) async {
    final repository = TestDownloadRepository();
    final manager = DownloadManager(
      repository: repository,
      clientFactory: () => DummyHttpClient(),
    );
    addTearDown(manager.dispose);
    await manager.init();

    await tester.pumpWidget(NetGetApp(manager: manager));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify title and subtitle
    expect(find.text('NDM'), findsOneWidget);
    expect(find.text('NetGet Download Manager'), findsOneWidget);

    // Verify Transfer Monitor summary card
    expect(find.text('Transfer Monitor'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget); // In monitor stat item
    expect(
      find.textContaining('Active ('),
      findsOneWidget,
    ); // In segmented button
    expect(find.text('Done'), findsOneWidget); // In monitor stat item
    expect(
      find.textContaining('Done ('),
      findsOneWidget,
    ); // In segmented button

    // Verify Empty State
    expect(find.text('No Downloads Yet'), findsOneWidget);

    // Verify Quick URL Input
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);

    // Verify Add Link FAB
    expect(find.text('Add Link'), findsOneWidget);
  });

  testWidgets('NetGetApp displays DownloadCard for existing tasks', (
    WidgetTester tester,
  ) async {
    final repository = TestDownloadRepository();
    repository.tasks = [
      DownloadTask(
        id: '1',
        url: 'https://example.com/big_file.zip',
        fileName: 'big_file.zip',
        savePath: '/tmp/big_file.zip',
        status: DownloadStatus.completed,
        downloadedBytes: 52428800,
        totalBytes: 52428800,
        createdAt: DateTime.now(),
      ),
    ];

    final manager = DownloadManager(
      repository: repository,
      clientFactory: () => DummyHttpClient(),
    );
    addTearDown(manager.dispose);
    await manager.init();

    await tester.pumpWidget(NetGetApp(manager: manager));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify task is displayed
    expect(find.byType(DownloadCard), findsOneWidget);
    expect(find.text('big_file.zip'), findsOneWidget);
    expect(find.text('Complete'), findsOneWidget);
  });

  testWidgets('DownloadCard hides error message when task transitions away from failed', (
    WidgetTester tester,
  ) async {
    final repository = TestDownloadRepository();
    final failedTask = DownloadTask(
      id: 'failed_1',
      url: 'https://example.com/err_file.zip',
      fileName: 'err_file.zip',
      savePath: '/tmp/err_file.zip',
      status: DownloadStatus.failed,
      errorMessage: 'Connection timed out',
      createdAt: DateTime.now(),
    );
    repository.tasks = [failedTask];

    final manager = DownloadManager(
      repository: repository,
      clientFactory: () => DummyHttpClient(),
    );
    addTearDown(manager.dispose);
    await manager.init();

    await tester.pumpWidget(NetGetApp(manager: manager));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify error is initially visible
    expect(find.text('Connection timed out'), findsOneWidget);

    // Retry download
    await manager.retryDownload('failed_1');
    await tester.pump();

    // Verify error is now completely gone from UI
    expect(find.text('Connection timed out'), findsNothing);
  });

  testWidgets('Empty state displays Add download button and paste chip', (
    WidgetTester tester,
  ) async {
    final repository = TestDownloadRepository();
    final manager = DownloadManager(
      repository: repository,
      clientFactory: () => DummyHttpClient(),
    );
    addTearDown(manager.dispose);
    await manager.init();

    await tester.pumpWidget(NetGetApp(manager: manager));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('No Downloads Yet'), findsOneWidget);
    expect(find.text('Add download'), findsOneWidget);
    expect(find.text('Paste from clipboard'), findsOneWidget);
  });

  testWidgets('Home screen groups and orders tasks: Active -> Queued/Paused -> Failed -> Completed with headers', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repository = TestDownloadRepository();
    final now = DateTime.now();
    repository.tasks = [
      DownloadTask(
        id: 'done_1',
        url: 'https://example.com/done.mp4',
        fileName: 'done.mp4',
        savePath: '/tmp/done.mp4',
        status: DownloadStatus.completed,
        createdAt: now.subtract(const Duration(minutes: 5)),
      ),
      DownloadTask(
        id: 'fail_1',
        url: 'https://example.com/fail.zip',
        fileName: 'fail.zip',
        savePath: '/tmp/fail.zip',
        status: DownloadStatus.failed,
        errorMessage: 'Connection timed out',
        createdAt: now.subtract(const Duration(minutes: 10)),
      ),
      DownloadTask(
        id: 'active_1',
        url: 'https://example.com/active.iso',
        fileName: 'active.iso',
        savePath: '/tmp/active.iso',
        status: DownloadStatus.downloading,
        downloadedBytes: 100,
        totalBytes: 500,
        createdAt: now.subtract(const Duration(minutes: 20)),
      ),
      DownloadTask(
        id: 'paused_1',
        url: 'https://example.com/paused.tar',
        fileName: 'paused.tar',
        savePath: '/tmp/paused.tar',
        status: DownloadStatus.paused,
        createdAt: now.subtract(const Duration(minutes: 15)),
      ),
    ];

    final manager = DownloadManager(
      repository: repository,
      clientFactory: () => DummyHttpClient(),
    );
    addTearDown(manager.dispose);
    await manager.init();

    await tester.pumpWidget(NetGetApp(manager: manager));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify section headers with counts are rendered
    expect(find.text('Active (1)'), findsOneWidget);
    expect(find.text('Queued & Paused (1)'), findsOneWidget);
    expect(find.text('Failed (1)'), findsOneWidget);
    expect(find.text('Completed (1)'), findsOneWidget);

    // Verify cards are all displayed
    expect(find.text('active.iso'), findsOneWidget);
    expect(find.text('paused.tar'), findsOneWidget);
    expect(find.text('fail.zip'), findsOneWidget);
    expect(find.text('done.mp4'), findsOneWidget);
  });

  testWidgets('About dialog does not contain Powered by Flutter', (WidgetTester tester) async {
    final repository = TestDownloadRepository();
    final manager = DownloadManager(
      repository: repository,
      clientFactory: () => DummyHttpClient(),
    );
    addTearDown(manager.dispose);
    await manager.init();

    await tester.pumpWidget(NetGetApp(manager: manager));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Open popup menu
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    // Tap About NDM
    await tester.tap(find.text('About NDM'));
    await tester.pumpAndSettle();

    // Verify custom about dialog is displayed
    expect(find.text('Version 1.0.0-rc2'), findsOneWidget);
    expect(find.text('NDM (NetGet Download Manager)'), findsOneWidget);

    // Verify "Powered by Flutter" is NEVER present
    expect(find.text('Powered by Flutter'), findsNothing);
    expect(find.textContaining('Powered by Flutter', findRichText: true), findsNothing);
  });
}
