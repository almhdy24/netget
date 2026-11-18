import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/models/download_status.dart';
import 'package:netget/models/download_task.dart';
import 'package:netget/services/nearby_share_service.dart';
import 'package:netget/ui/widgets/nearby_share_sheet.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late Directory tempDir;
  late File sampleFile;
  late NearbyShareService shareService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('netget_nearby_ui_test_');
    sampleFile = File('${tempDir.path}/sample.zip');
    await sampleFile.writeAsBytes(List.generate(1024, (i) => i % 256));
    shareService = NearbyShareService();
  });

  tearDown(() async {
    await shareService.stopSharing();
    shareService.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('NearbyShareSheet renders QR code, link, and metrics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final task = DownloadTask(
      id: 'task_share_1',
      url: 'https://example.com/sample.zip',
      fileName: 'sample.zip',
      savePath: sampleFile.path,
      totalBytes: 1024,
      status: DownloadStatus.completed,
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: NearbyShareSheet(
              task: task,
              customService: shareService,
              initialShareUrl: 'http://127.0.0.1:8080/d/123/sample.zip',
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('شارك بالقرب (بدون إنترنت)'), findsOneWidget);
    expect(find.text('sample.zip'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('/d/'), findsOneWidget);
    expect(find.text('الأجهزة المتصلة'), findsOneWidget);
    expect(find.text('المنقول'), findsOneWidget);
  });
}
