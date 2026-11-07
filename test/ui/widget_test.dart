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

void main() {
  testWidgets('NetGetApp renders home dashboard, empty state, and controls', (
    WidgetTester tester,
  ) async {
    final repository = TestDownloadRepository();
    final manager = DownloadManager(repository: repository);
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

    final manager = DownloadManager(repository: repository);
    addTearDown(manager.dispose);
    await manager.init();

    await tester.pumpWidget(NetGetApp(manager: manager));
    await tester.pumpAndSettle();

    // Verify task is displayed
    expect(find.byType(DownloadCard), findsOneWidget);
    expect(find.text('big_file.zip'), findsOneWidget);
    expect(find.text('Complete'), findsOneWidget);
  });
}
