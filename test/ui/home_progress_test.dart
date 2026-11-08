import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/segment_planner.dart';
import 'package:netget/data/download_repository.dart';
import 'package:netget/main.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/download_manager.dart';

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

void main() {
  testWidgets('(a) single-connection progress ticks update the Home card progress bar and percent within one frame', (
    WidgetTester tester,
  ) async {
    final repository = TestDownloadRepository();
    final initialTask = DownloadTask(
      id: 'task_single',
      url: 'https://example.com/single.bin',
      fileName: 'single.bin',
      savePath: '/tmp/single.bin',
      status: DownloadStatus.downloading,
      downloadedBytes: 0,
      totalBytes: 1000,
      connectionCount: 1,
      createdAt: DateTime.now(),
    );
    repository.tasks = [initialTask];

    final manager = DownloadManager(repository: repository);
    addTearDown(manager.dispose);
    await manager.init();

    await tester.pumpWidget(NetGetApp(manager: manager));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify initial 0% state
    expect(find.text('single.bin'), findsOneWidget);
    expect(find.textContaining('0.0%'), findsOneWidget);

    final initialIndicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(initialIndicator.value, 0.0);

    // Emit a single-connection progress tick to 45% (450 bytes)
    manager.emitProgressTick(
      'task_single',
      downloadedBytes: 450,
      totalBytes: 1000,
      speedBytesPerSec: 50000,
    );

    // Verify it updates within one frame (a single pump with no elapsed duration)
    await tester.pump();

    expect(find.textContaining('45.0%'), findsOneWidget);
    final updatedIndicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(updatedIndicator.value, 0.45);
  });

  testWidgets('(b) multi-connection ticks do the same', (
    WidgetTester tester,
  ) async {
    final repository = TestDownloadRepository();
    final initialSegments = [
      DownloadSegment(index: 0, startByte: 0, endByte: 499, downloadedBytes: 0),
      DownloadSegment(index: 1, startByte: 500, endByte: 999, downloadedBytes: 0),
      DownloadSegment(index: 2, startByte: 1000, endByte: 1499, downloadedBytes: 0),
      DownloadSegment(index: 3, startByte: 1500, endByte: 1999, downloadedBytes: 0),
    ];

    final initialTask = DownloadTask(
      id: 'task_multi',
      url: 'https://example.com/multi.bin',
      fileName: 'multi.bin',
      savePath: '/tmp/multi.bin',
      status: DownloadStatus.downloading,
      downloadedBytes: 0,
      totalBytes: 2000,
      connectionCount: 4,
      segments: initialSegments,
      createdAt: DateTime.now(),
    );
    repository.tasks = [initialTask];

    final manager = DownloadManager(repository: repository);
    addTearDown(manager.dispose);
    await manager.init();

    await tester.pumpWidget(NetGetApp(manager: manager));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify initial state
    expect(find.text('multi.bin'), findsOneWidget);
    expect(find.textContaining('0.0%'), findsOneWidget);

    final updatedSegments = [
      DownloadSegment(index: 0, startByte: 0, endByte: 499, downloadedBytes: 250),
      DownloadSegment(index: 1, startByte: 500, endByte: 999, downloadedBytes: 250),
      DownloadSegment(index: 2, startByte: 1000, endByte: 1499, downloadedBytes: 250),
      DownloadSegment(index: 3, startByte: 1500, endByte: 1999, downloadedBytes: 250),
    ];
    final totalDownloaded = updatedSegments.fold<int>(0, (int sum, DownloadSegment s) => sum + s.downloadedBytes);

    // Emit multi-connection progress tick: 1000 of 2000 bytes (50.0%)
    manager.emitProgressTick(
      'task_multi',
      downloadedBytes: totalDownloaded,
      totalBytes: 2000,
      speedBytesPerSec: 150000,
      segments: updatedSegments,
    );

    // Verify it updates within one frame
    await tester.pump();

    expect(find.textContaining('50.0%'), findsOneWidget);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.50);
  });

  testWidgets('(c) unknown totalBytes shows an indeterminate bar, not 0%', (
    WidgetTester tester,
  ) async {
    final repository = TestDownloadRepository();
    final initialTask = DownloadTask(
      id: 'task_unknown',
      url: 'https://example.com/stream.bin',
      fileName: 'stream.bin',
      savePath: '/tmp/stream.bin',
      status: DownloadStatus.downloading,
      downloadedBytes: 1024,
      totalBytes: 0, // Unknown total size
      connectionCount: 1,
      createdAt: DateTime.now(),
    );
    repository.tasks = [initialTask];

    final manager = DownloadManager(repository: repository);
    addTearDown(manager.dispose);
    await manager.init();

    await tester.pumpWidget(NetGetApp(manager: manager));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('stream.bin'), findsOneWidget);

    // LinearProgressIndicator value must be null for indeterminate bar
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, isNull);

    // UI must not display 0% or 0.0%
    expect(find.textContaining('0%'), findsNothing);
    expect(find.textContaining('0.0%'), findsNothing);
  });
}
