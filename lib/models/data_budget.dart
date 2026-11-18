import 'package:flutter/material.dart';

/// Network policy for downloads and queues.
enum NetworkPolicy {
  anyNetwork('anyNetwork', 'أي شبكة', 'Any Network'),
  wifiOrFreeWindow(
    'wifiOrFreeWindow',
    'واي فاي أو الباقة المجانية',
    'Wi-Fi or Free Window',
  ),
  wifiOnly('wifiOnly', 'واي فاي فقط', 'Wi-Fi Only');

  final String key;
  final String labelAr;
  final String labelEn;

  const NetworkPolicy(this.key, this.labelAr, this.labelEn);

  static NetworkPolicy fromString(String? val) {
    if (val == null) return NetworkPolicy.anyNetwork;
    return NetworkPolicy.values.firstWhere(
      (p) => p.name == val || p.key == val,
      orElse: () => NetworkPolicy.anyNetwork,
    );
  }
}

/// Represents a recurring time window (e.g. night bundle from 00:00 to 06:00).
class FreeWindow {
  final String label;
  final TimeOfDay start;
  final TimeOfDay end;
  final List<int> daysOfWeek; // 1 = Monday, 7 = Sunday (DateTime.weekday)

  const FreeWindow({
    this.label = '',
    required this.start,
    required this.end,
    this.daysOfWeek = const [1, 2, 3, 4, 5, 6, 7],
  });

  /// Checks if [time] falls inside this free window.
  bool contains(DateTime time) {
    if (!daysOfWeek.contains(time.weekday)) return false;

    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    final currentMinutes = time.hour * 60 + time.minute;

    if (startMinutes <= endMinutes) {
      // Intra-day window (e.g. 02:00 to 06:00)
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } else {
      // Overnight window spanning midnight (e.g. 23:00 to 07:00)
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'startHour': start.hour,
    'startMinute': start.minute,
    'endHour': end.hour,
    'endMinute': end.minute,
    'daysOfWeek': daysOfWeek,
  };

  factory FreeWindow.fromJson(Map<String, dynamic> json) {
    return FreeWindow(
      label: json['label'] as String? ?? '',
      start: TimeOfDay(
        hour: json['startHour'] as int? ?? 0,
        minute: json['startMinute'] as int? ?? 0,
      ),
      end: TimeOfDay(
        hour: json['endHour'] as int? ?? 6,
        minute: json['endMinute'] as int? ?? 0,
      ),
      daysOfWeek:
          (json['daysOfWeek'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          const [1, 2, 3, 4, 5, 6, 7],
    );
  }
}

/// Aggregate usage statistics for data budget tracking.
class BudgetUsageSummary {
  final int totalBytes;
  final int countedBytes;
  final int freeBytes;
  final int wifiBytes;
  final int mobileBytes;
  final int? budgetLimitBytes;
  final int resetDay;
  final int daysRemainingInPeriod;

  const BudgetUsageSummary({
    required this.totalBytes,
    required this.countedBytes,
    required this.freeBytes,
    required this.wifiBytes,
    required this.mobileBytes,
    this.budgetLimitBytes,
    this.resetDay = 1,
    this.daysRemainingInPeriod = 30,
  });

  double get usagePercent {
    if (budgetLimitBytes == null || budgetLimitBytes! <= 0) return 0.0;
    return (countedBytes / budgetLimitBytes!).clamp(0.0, 1.0);
  }

  int get remainingBytes {
    if (budgetLimitBytes == null || budgetLimitBytes! <= 0) return 0;
    return (budgetLimitBytes! - countedBytes).clamp(0, budgetLimitBytes!);
  }

  bool get isExceeded =>
      budgetLimitBytes != null &&
      budgetLimitBytes! > 0 &&
      countedBytes >= budgetLimitBytes!;
}
