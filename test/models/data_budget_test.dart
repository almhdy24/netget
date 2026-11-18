import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/models/data_budget.dart';

void main() {
  group('FreeWindow Tests', () {
    test('intra-day free window (02:00 to 06:00)', () {
      const window = FreeWindow(
        start: TimeOfDay(hour: 2, minute: 0),
        end: TimeOfDay(hour: 6, minute: 0),
        daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
      );

      // 01:59 -> outside
      expect(window.contains(DateTime(2026, 1, 1, 1, 59)), isFalse);
      // 02:00 -> inside
      expect(window.contains(DateTime(2026, 1, 1, 2, 0)), isTrue);
      // 04:30 -> inside
      expect(window.contains(DateTime(2026, 1, 1, 4, 30)), isTrue);
      // 06:00 -> outside
      expect(window.contains(DateTime(2026, 1, 1, 6, 0)), isFalse);
      // 12:00 -> outside
      expect(window.contains(DateTime(2026, 1, 1, 12, 0)), isFalse);
    });

    test('overnight free window spanning midnight (23:00 to 07:00)', () {
      const window = FreeWindow(
        start: TimeOfDay(hour: 23, minute: 0),
        end: TimeOfDay(hour: 7, minute: 0),
        daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
      );

      // 22:59 -> outside
      expect(window.contains(DateTime(2026, 1, 1, 22, 59)), isFalse);
      // 23:00 -> inside
      expect(window.contains(DateTime(2026, 1, 1, 23, 0)), isTrue);
      // 23:45 -> inside
      expect(window.contains(DateTime(2026, 1, 1, 23, 45)), isTrue);
      // 01:30 (next day) -> inside
      expect(window.contains(DateTime(2026, 1, 2, 1, 30)), isTrue);
      // 06:59 -> inside
      expect(window.contains(DateTime(2026, 1, 2, 6, 59)), isTrue);
      // 07:00 -> outside
      expect(window.contains(DateTime(2026, 1, 2, 7, 0)), isFalse);
      // 15:00 -> outside
      expect(window.contains(DateTime(2026, 1, 2, 15, 0)), isFalse);
    });

    test('respects day of week filters', () {
      // Free window only on Friday (5) and Saturday (6)
      const weekendWindow = FreeWindow(
        start: TimeOfDay(hour: 1, minute: 0),
        end: TimeOfDay(hour: 5, minute: 0),
        daysOfWeek: [DateTime.friday, DateTime.saturday],
      );

      // 2026-01-01 was Thursday (weekday 4)
      final thursdayTime = DateTime(2026, 1, 1, 2, 0);
      expect(thursdayTime.weekday, equals(DateTime.thursday));
      expect(weekendWindow.contains(thursdayTime), isFalse);

      // 2026-01-02 was Friday (weekday 5)
      final fridayTime = DateTime(2026, 1, 2, 2, 0);
      expect(fridayTime.weekday, equals(DateTime.friday));
      expect(weekendWindow.contains(fridayTime), isTrue);
    });

    test('serializes and deserializes correctly to/from JSON', () {
      const window = FreeWindow(
        start: TimeOfDay(hour: 1, minute: 30),
        end: TimeOfDay(hour: 5, minute: 45),
        daysOfWeek: [1, 3, 5],
      );

      final json = window.toJson();
      final restored = FreeWindow.fromJson(json);

      expect(restored.start.hour, equals(1));
      expect(restored.start.minute, equals(30));
      expect(restored.end.hour, equals(5));
      expect(restored.end.minute, equals(45));
      expect(restored.daysOfWeek, equals([1, 3, 5]));
    });
  });

  group('BudgetUsageSummary Tests', () {
    test('calculates usage percent and remaining bytes correctly', () {
      const summary = BudgetUsageSummary(
        totalBytes: 5 * 1024 * 1024 * 1024,
        countedBytes: 8 * 1024 * 1024 * 1024,
        freeBytes: 2 * 1024 * 1024 * 1024,
        wifiBytes: 5 * 1024 * 1024 * 1024,
        mobileBytes: 10 * 1024 * 1024 * 1024,
        budgetLimitBytes: 10 * 1024 * 1024 * 1024, // 10 GB
      );

      expect(summary.usagePercent, closeTo(0.8, 0.001));
      expect(summary.remainingBytes, equals(2 * 1024 * 1024 * 1024));
      expect(summary.isExceeded, isFalse);
    });

    test('flags isExceeded when countedBytes reaches or exceeds limit', () {
      const summary = BudgetUsageSummary(
        totalBytes: 12 * 1024 * 1024 * 1024,
        countedBytes: 10 * 1024 * 1024 * 1024,
        freeBytes: 2 * 1024 * 1024 * 1024,
        wifiBytes: 0,
        mobileBytes: 12 * 1024 * 1024 * 1024,
        budgetLimitBytes: 10 * 1024 * 1024 * 1024,
      );

      expect(summary.isExceeded, isTrue);
      expect(summary.remainingBytes, equals(0));
    });
  });
}
