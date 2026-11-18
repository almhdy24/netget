import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/models/app_settings.dart';
import 'package:netget/models/data_budget.dart';
import 'package:netget/services/data_budget_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DataBudgetService Tests', () {
    late Database db;
    late DataBudgetService budgetService;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE usage_ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp INTEGER NOT NULL,
          task_id TEXT NOT NULL,
          bytes INTEGER NOT NULL,
          network_type TEXT NOT NULL
        )
      ''');

      budgetService = DataBudgetService(
        dbResolver: () async => db,
        networkTypeResolver: () async => 'wifi',
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('computes billing cycle boundaries correctly', () {
      // 1. Day of month >= resetDay: cycle starts current month
      final date1 = DateTime(2026, 5, 15);
      final start1 = budgetService.getBillingCycleStart(date1, 10);
      expect(start1, equals(DateTime(2026, 5, 10)));
      expect(
        budgetService.getBillingCycleEnd(start1),
        equals(DateTime(2026, 6, 10)),
      );

      // 2. Day of month < resetDay: cycle starts previous month
      final date2 = DateTime(2026, 5, 5);
      final start2 = budgetService.getBillingCycleStart(date2, 10);
      expect(start2, equals(DateTime(2026, 4, 10)));
      expect(
        budgetService.getBillingCycleEnd(start2),
        equals(DateTime(2026, 5, 10)),
      );

      // 3. Year wrap-around: January 5 with reset day 15 -> starts Dec 15 of prior year
      final date3 = DateTime(2026, 1, 5);
      final start3 = budgetService.getBillingCycleStart(date3, 15);
      expect(start3, equals(DateTime(2025, 12, 15)));
      expect(
        budgetService.getBillingCycleEnd(start3),
        equals(DateTime(2026, 1, 15)),
      );
    });

    test('records usage in ledger and aggregates summary accurately', () async {
      final now = DateTime(2026, 5, 12, 10, 0);

      // Record 100 MB on wifi
      await budgetService.recordUsage(
        taskId: 't1',
        bytes: 100 * 1024 * 1024,
        networkType: 'wifi',
        timestamp: DateTime(2026, 5, 10, 12, 0),
      );

      // Record 200 MB on counted mobile
      await budgetService.recordUsage(
        taskId: 't2',
        bytes: 200 * 1024 * 1024,
        networkType: 'mobile',
        timestamp: DateTime(2026, 5, 11, 14, 0),
      );

      // Record 50 MB in free night window
      await budgetService.recordUsage(
        taskId: 't3',
        bytes: 50 * 1024 * 1024,
        networkType: 'free_mobile',
        timestamp: DateTime(2026, 5, 12, 3, 0),
      );

      // Out-of-cycle record (April): should not count towards May budget
      await budgetService.recordUsage(
        taskId: 't0',
        bytes: 500 * 1024 * 1024,
        networkType: 'mobile',
        timestamp: DateTime(2026, 4, 25, 10, 0),
      );

      const settings = AppSettings(
        budgetResetDay: 1,
        monthlyBudgetBytes: 1024 * 1024 * 1024, // 1 GB
      );

      final summary = await budgetService.getSummary(
        settings: settings,
        now: now,
      );

      expect(summary.wifiBytes, equals(100 * 1024 * 1024));
      expect(summary.countedBytes, equals(200 * 1024 * 1024));
      expect(summary.freeBytes, equals(50 * 1024 * 1024));
      expect(summary.mobileBytes, equals(250 * 1024 * 1024));
      expect(summary.totalBytes, equals(350 * 1024 * 1024));
      expect(summary.isExceeded, isFalse);
    });

    test('enforces wifiOnly policy when on cellular', () async {
      const settings = AppSettings(wifiOnly: false);

      final resWifi = await budgetService.checkAllowed(
        policy: NetworkPolicy.wifiOnly,
        settings: settings,
        isWifiOverride: true,
      );
      expect(resWifi.isAllowed, isTrue);

      final resMobile = await budgetService.checkAllowed(
        policy: NetworkPolicy.wifiOnly,
        settings: settings,
        isWifiOverride: false,
      );
      expect(resMobile.isAllowed, isFalse);
      expect(resMobile.pauseReason, equals('network'));
    });

    test('enforces wifiOrFreeWindow policy', () async {
      const nightWindow = FreeWindow(
        start: TimeOfDay(hour: 0, minute: 0),
        end: TimeOfDay(hour: 6, minute: 0),
      );

      const settings = AppSettings(freeWindows: [nightWindow]);

      // 14:00 (outside night window) on mobile data -> paused
      final resDaytimeMobile = await budgetService.checkAllowed(
        policy: NetworkPolicy.wifiOrFreeWindow,
        settings: settings,
        isWifiOverride: false,
        now: DateTime(2026, 5, 12, 14, 0),
      );
      expect(resDaytimeMobile.isAllowed, isFalse);
      expect(resDaytimeMobile.pauseReason, equals('network'));

      // 03:00 (inside night window) on mobile data -> allowed!
      final resNightMobile = await budgetService.checkAllowed(
        policy: NetworkPolicy.wifiOrFreeWindow,
        settings: settings,
        isWifiOverride: false,
        now: DateTime(2026, 5, 12, 3, 0),
      );
      expect(resNightMobile.isAllowed, isTrue);

      // Anytime on Wi-Fi -> allowed!
      final resWifi = await budgetService.checkAllowed(
        policy: NetworkPolicy.wifiOrFreeWindow,
        settings: settings,
        isWifiOverride: true,
        now: DateTime(2026, 5, 12, 14, 0),
      );
      expect(resWifi.isAllowed, isTrue);
    });

    test('enforces budgetHardStop when monthly cap reached', () async {
      // Record 1.1 GB mobile usage
      await budgetService.recordUsage(
        taskId: 'heavy_task',
        bytes: 1100 * 1024 * 1024,
        networkType: 'mobile',
        timestamp: DateTime(2026, 5, 5),
      );

      const settings = AppSettings(
        monthlyBudgetBytes: 1000 * 1024 * 1024, // 1 GB cap
        budgetResetDay: 1,
        budgetHardStop: true,
      );

      final res = await budgetService.checkAllowed(
        policy: NetworkPolicy.anyNetwork,
        settings: settings,
        isWifiOverride: false,
        now: DateTime(2026, 5, 12),
      );

      expect(res.isAllowed, isFalse);
      expect(res.pauseReason, equals('budget'));
      expect(res.message, contains('budget'));
    });
  });
}
