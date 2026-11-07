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
    await tester.pumpAndSettle();

    // Verify title and subtitle
    expect(find.text('NetGet'), findsOneWidget);
    expect(find.text('Download Manager'), findsOneWidget);

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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    // Verify error is initially visible
    expect(find.text('Connection timed out'), findsOneWidget);

    // Retry download
    await manager.retryDownload('failed_1');
    await tester.pump();

    // Verify error is now completely gone from UI
    expect(find.text('Connection timed out'), findsNothing);
  });
}
