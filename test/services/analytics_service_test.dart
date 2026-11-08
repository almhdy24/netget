import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/services/analytics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnalyticsService Bucketing', () {
    test('sizeBucket formats coarse ranges without exact byte counts', () {
      expect(AnalyticsService.sizeBucket(-1), 'unknown');
      expect(AnalyticsService.sizeBucket(500 * 1024), '<1MB');
      expect(AnalyticsService.sizeBucket(5 * 1024 * 1024), '1-10MB');
      expect(AnalyticsService.sizeBucket(25 * 1024 * 1024), '10-50MB');
      expect(AnalyticsService.sizeBucket(75 * 1024 * 1024), '50-100MB');
      expect(AnalyticsService.sizeBucket(250 * 1024 * 1024), '100-500MB');
      expect(AnalyticsService.sizeBucket(800 * 1024 * 1024), '500MB-1GB');
      expect(AnalyticsService.sizeBucket(2 * 1024 * 1024 * 1024), '>1GB');
    });

    test('speedBucket formats coarse speed ranges', () {
      expect(AnalyticsService.speedBucket(-5), '0kbps');
      expect(AnalyticsService.speedBucket(0), '0kbps');
      expect(AnalyticsService.speedBucket(50), '<100kbps');
      expect(AnalyticsService.speedBucket(250), '100-500kbps');
      expect(AnalyticsService.speedBucket(800), '500kbps-1mbps');
      expect(AnalyticsService.speedBucket(2500), '1-5mbps');
      expect(AnalyticsService.speedBucket(7500), '5-10mbps');
      expect(AnalyticsService.speedBucket(15000), '>10mbps');
    });
  });

  group('AnalyticsService Non-blocking and Resilience', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('analytics_test_');
    });

    tearDown(() async {
      await AnalyticsService.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('initializes and executes tracking without throwing', () async {
      final bufferFile = '${tempDir.path}/buffer.json';

      await AnalyticsService.initialize(
        projectKey: 'ak_live_test_dummy_key_1234567890',
        appVersion: '1.0.0-test',
        debug: true,
        storagePath: bufferFile,
      );

      expect(AnalyticsService.isEnabled, isTrue);

      // Track diverse events
      AnalyticsService.trackAppOpen();
      AnalyticsService.trackAppBackground();
      AnalyticsService.screenView('test_screen');
      AnalyticsService.trackDownloadAdded(source: 'link', category: 'documents');
      AnalyticsService.trackDownloadStarted(connectionCount: 4);
      AnalyticsService.trackDownloadPaused();
      AnalyticsService.trackDownloadResumed();
      AnalyticsService.trackDownloadCancelled();
      AnalyticsService.trackDownloadRetried();
      AnalyticsService.trackDownloadCompleted(
        totalBytes: 15 * 1024 * 1024,
        durationSeconds: 12,
        avgSpeedBytesPerSec: 1.25 * 1024 * 1024,
        category: 'archives',
      );
      AnalyticsService.trackDownloadFailed(errorType: 'http404', httpStatus: 404);
      AnalyticsService.trackSettingChanged(settingName: 'speed_mode', settingValue: 'normal');
      AnalyticsService.trackStatsViewed(view: 'summary_card');
      AnalyticsService.recordError(
        Exception('Test error'),
        StackTrace.current,
        context: 'unit_test',
        fatal: false,
      );

      // Toggle opt-out
      await AnalyticsService.setEnabled(false);
      expect(AnalyticsService.isEnabled, isFalse);

      await AnalyticsService.setEnabled(true);
      expect(AnalyticsService.isEnabled, isTrue);
    });
  });
}
