import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/constants.dart';
import 'package:netget/core/theme.dart';
import 'package:netget/data/download_repository.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/download_manager.dart';
import 'package:netget/ui/details/download_details_screen.dart';
import 'package:netget/ui/home_screen.dart';
import 'package:netget/ui/widgets/add_download_sheet.dart';
import 'package:netget/ui/widgets/download_card.dart';

class MockRepo implements DownloadRepository {
  List<DownloadTask> tasks = [];
  @override
  Future<List<DownloadTask>> loadTasks() async => tasks;
  @override
  Future<void> saveTasks(List<DownloadTask> t) async => tasks = t;
  @override
  Future<void> saveTask(DownloadTask t) async => tasks.add(t);
  @override
  Future<void> deleteTask(String id) async => tasks.removeWhere((t) => t.id == id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockRepo repo;
  late DownloadManager manager;

  setUp(() async {
    repo = MockRepo();
    manager = DownloadManager(repository: repo);
    await manager.init();
  });

  testWidgets('Physical Inset Test: 3-Button Navigation (48dp) prevents FAB & card overlap', (tester) async {
    // Configure physical dimensions: 1080x2400 @ 3x (360x800 logical dp)
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    // Android 15 3-button navigation: 48dp bottom bar, 48dp top status bar
    tester.view.padding = const FakeViewPadding(top: 144, bottom: 144, left: 0, right: 0);
    tester.view.viewPadding = const FakeViewPadding(top: 144, bottom: 144, left: 0, right: 0);

    // Add a dummy task
    repo.tasks = [
      DownloadTask(
        id: 'task_inset_1',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        savePath: '/tmp/file.zip',
        totalBytes: 1000000,
        downloadedBytes: 500000,
        status: DownloadStatus.downloading,
        createdAt: DateTime.now(),
      ),
    ];
    await manager.init(forceReload: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: NetGetTheme.lightTheme(),
        home: HomeScreen(
          manager: manager,
          themeModeNotifier: ValueNotifier(ThemeMode.light),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify FAB is located above the 48dp navigation bar
    final fabFinder = find.byType(FloatingActionButton);
    expect(fabFinder, findsOneWidget);
    final fabBottom = tester.getBottomRight(fabFinder).dy;
    // Screen height is 800 logical dp. Bottom bar is 48dp (752 to 800).
    // FAB should be at 800 - 48 (bottom padding) - 16 (margin) = 736dp
    expect(fabBottom, lessThanOrEqualTo(752.0), reason: 'FAB must never enter the 48dp 3-button navigation area');

    // Reset view
    tester.view.resetPhysicalSize();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });

  testWidgets('Physical Inset Test: AddDownloadSheet pads for 3-button nav and moves above keyboard', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    // 3-button navigation (48dp bottom)
    tester.view.padding = const FakeViewPadding(top: 144, bottom: 144, left: 0, right: 0);
    tester.view.viewPadding = const FakeViewPadding(top: 144, bottom: 144, left: 0, right: 0);

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: NetGetTheme.darkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    // Open sheet without keyboard
    AddDownloadSheet.show(ctx, manager: manager);
    await tester.pumpAndSettle();

    // Scroll to bottom of sheet
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    final startBtn = find.text('Start now');
    expect(startBtn, findsOneWidget);
    final btnBottom = tester.getBottomRight(startBtn).dy;
    // Screen height is 800. Bottom bar is 752..800.
    // The button must be above 752dp
    expect(btnBottom, lessThanOrEqualTo(752.0), reason: 'Action buttons must be completely clear of 3-button navigation bar');

    // Simulate software keyboard opening (300dp viewInset)
    tester.view.viewInsets = const FakeViewPadding(bottom: 900); // 300 logical dp
    await tester.pumpAndSettle();

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    final btnBottomWithKeyboard = tester.getBottomRight(startBtn).dy;
    // Available height with 300dp keyboard is 500dp.
    expect(btnBottomWithKeyboard, lessThanOrEqualTo(500.0), reason: 'Action buttons must stay completely visible above software keyboard');

    // Dismiss sheet and reset view
    tester.view.resetViewInsets();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    tester.view.resetPhysicalSize();
  });

  testWidgets('Physical Inset Test: DownloadDetailsScreen standalone pads bottom content', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 144, bottom: 144, left: 0, right: 0);
    tester.view.viewPadding = const FakeViewPadding(top: 144, bottom: 144, left: 0, right: 0);

    repo.tasks = [
      DownloadTask(
        id: 'task_details_1',
        url: 'https://example.com/iso.img',
        fileName: 'iso.img',
        savePath: '/tmp/iso.img',
        totalBytes: 5000000,
        status: DownloadStatus.downloading,
        createdAt: DateTime.now(),
      ),
    ];
    await manager.init(forceReload: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: NetGetTheme.lightTheme(),
        home: DownloadDetailsScreen(manager: manager, taskId: 'task_details_1'),
      ),
    );
    await tester.pumpAndSettle();

    // Verify ScrollView has bottom padding equal to 16 + 48 = 64
    final scrollFinder = find.byType(SingleChildScrollView);
    expect(scrollFinder, findsOneWidget);
    final scrollWidget = tester.widget<SingleChildScrollView>(scrollFinder);
    final padding = scrollWidget.padding as EdgeInsets;
    expect(padding.bottom, equals(64.0), reason: 'Bottom padding must include 48dp system bar inset');

    tester.view.resetPadding();
    tester.view.resetViewPadding();
    tester.view.resetPhysicalSize();
  });
}
