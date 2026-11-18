import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../data/sqlite_download_repository.dart';
import '../models/app_settings.dart';
import '../models/data_budget.dart';

class NetworkCheckResult {
  final bool isAllowed;
  final String? pauseReason;
  final String? message;

  const NetworkCheckResult({
    required this.isAllowed,
    this.pauseReason,
    this.message,
  });

  const NetworkCheckResult.allowed()
    : isAllowed = true,
      pauseReason = null,
      message = null;
  const NetworkCheckResult.paused({
    required this.pauseReason,
    required this.message,
  }) : isAllowed = false;
}

/// Service managing data budget tracking, accounting ledger, and network policy enforcement (§5.1).
class DataBudgetService {
  static const MethodChannel _platform = MethodChannel(
    'com.elmahdi.netget/engine',
  );
  final Future<Database> Function()? _dbResolver;
  final Future<String> Function()? _networkTypeResolver;

  static DataBudgetService? _instance;
  static DataBudgetService get instance => _instance ??= DataBudgetService();
  static set instance(DataBudgetService s) => _instance = s;

  DataBudgetService({
    Future<Database> Function()? dbResolver,
    Future<String> Function()? networkTypeResolver,
  }) : _dbResolver = dbResolver,
       _networkTypeResolver = networkTypeResolver;

  Future<String> getNetworkType() async {
    final resolver = _networkTypeResolver;
    if (resolver != null) {
      return await resolver();
    }
    if (Platform.isAndroid &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        final res = await _platform
            .invokeMethod<String>('getNetworkType')
            .timeout(const Duration(milliseconds: 500));
        if (res != null && res.isNotEmpty) return res;
      } catch (_) {}
    }
    return 'wifi';
  }

  /// Records downloaded bytes into SQLite `usage_ledger`.
  Future<void> recordUsage({
    required String taskId,
    required int bytes,
    required String networkType,
    DateTime? timestamp,
  }) async {
    if (bytes <= 0) return;
    try {
      final Database db = _dbResolver != null
          ? await _dbResolver()
          : await SqliteDownloadRepository().database;
      final ts = (timestamp ?? DateTime.now()).millisecondsSinceEpoch;
      await db.insert('usage_ledger', {
        'timestamp': ts,
        'task_id': taskId,
        'bytes': bytes,
        'network_type': networkType,
      });
    } catch (_) {}
  }

  /// Returns whether [now] falls inside any configured free windows.
  bool isFreeWindow({required List<FreeWindow> freeWindows, DateTime? now}) {
    if (freeWindows.isEmpty) return false;
    final current = now ?? DateTime.now();
    for (final w in freeWindows) {
      if (w.contains(current)) return true;
    }
    return false;
  }

  /// Computes the start and end of the billing period for a given [resetDay].
  DateTime getBillingCycleStart(DateTime now, int resetDay) {
    final day = resetDay.clamp(1, 28);
    if (now.day >= day) {
      return DateTime(now.year, now.month, day);
    } else {
      final prevMonth = now.month == 1 ? 12 : now.month - 1;
      final prevYear = now.month == 1 ? now.year - 1 : now.year;
      return DateTime(prevYear, prevMonth, day);
    }
  }

  DateTime getBillingCycleEnd(DateTime cycleStart) {
    final nextMonth = cycleStart.month == 12 ? 1 : cycleStart.month + 1;
    final nextYear = cycleStart.month == 12
        ? cycleStart.year + 1
        : cycleStart.year;
    return DateTime(nextYear, nextMonth, cycleStart.day);
  }

  /// Returns aggregate usage statistics for the current billing cycle.
  Future<BudgetUsageSummary> getSummary({
    required AppSettings settings,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final cycleStart = getBillingCycleStart(current, settings.budgetResetDay);
    final cycleEnd = getBillingCycleEnd(cycleStart);
    final daysRemaining = cycleEnd.difference(current).inDays.clamp(0, 31);

    int wifiBytes = 0;
    int countedBytes = 0;
    int freeBytes = 0;

    try {
      final Database db = _dbResolver != null
          ? await _dbResolver()
          : await SqliteDownloadRepository().database;

      final List<Map<String, Object?>> rows = await db.rawQuery(
        '''
        SELECT network_type, SUM(bytes) as sum_bytes
        FROM usage_ledger
        WHERE timestamp >= ? AND timestamp < ?
        GROUP BY network_type
      ''',
        [cycleStart.millisecondsSinceEpoch, cycleEnd.millisecondsSinceEpoch],
      );

      for (final row in rows) {
        final type = row['network_type'] as String? ?? 'wifi';
        final sum = (row['sum_bytes'] as int?) ?? 0;
        if (type == 'wifi') {
          wifiBytes += sum;
        } else if (type == 'free_mobile') {
          freeBytes += sum;
        } else if (type == 'mobile') {
          countedBytes += sum;
        } else {
          wifiBytes += sum;
        }
      }
    } catch (_) {}

    final mobileBytes = countedBytes + freeBytes;
    final totalBytes = wifiBytes + mobileBytes;

    return BudgetUsageSummary(
      totalBytes: totalBytes,
      countedBytes: countedBytes,
      freeBytes: freeBytes,
      wifiBytes: wifiBytes,
      mobileBytes: mobileBytes,
      budgetLimitBytes: settings.monthlyBudgetBytes,
      resetDay: settings.budgetResetDay,
      daysRemainingInPeriod: daysRemaining,
    );
  }

  /// Evaluates whether a download task is allowed to run given its network policy and current network/budget.
  Future<NetworkCheckResult> checkAllowed({
    required NetworkPolicy policy,
    required AppSettings settings,
    bool? isWifiOverride,
    DateTime? now,
  }) async {
    final netType = isWifiOverride != null
        ? (isWifiOverride ? 'wifi' : 'mobile')
        : await getNetworkType();

    if (netType == 'none') {
      return const NetworkCheckResult.paused(
        pauseReason: 'network',
        message: 'No connection (waiting for network...)',
      );
    }

    final isWifi = netType == 'wifi' || netType == 'ethernet';

    // 1. Wi-Fi Only enforcement
    if (policy == NetworkPolicy.wifiOnly || settings.wifiOnly) {
      if (!isWifi) {
        return const NetworkCheckResult.paused(
          pauseReason: 'network',
          message: 'Paused: Wi-Fi only network policy active',
        );
      }
      return const NetworkCheckResult.allowed();
    }

    // 2. Wi-Fi or Free Window enforcement
    if (policy == NetworkPolicy.wifiOrFreeWindow) {
      if (isWifi) return const NetworkCheckResult.allowed();
      final insideFree = isFreeWindow(
        freeWindows: settings.freeWindows,
        now: now,
      );
      if (!insideFree) {
        return const NetworkCheckResult.paused(
          pauseReason: 'network',
          message: 'Paused: waiting for Wi-Fi or free data window',
        );
      }
      return const NetworkCheckResult.allowed();
    }

    // 3. Any Network: check mobile data budget cap
    if (!isWifi) {
      final insideFree = isFreeWindow(
        freeWindows: settings.freeWindows,
        now: now,
      );
      if (insideFree) {
        return const NetworkCheckResult.allowed();
      }

      if (settings.monthlyBudgetBytes != null &&
          settings.monthlyBudgetBytes! > 0) {
        final summary = await getSummary(settings: settings, now: now);
        if (summary.isExceeded && settings.budgetHardStop) {
          return const NetworkCheckResult.paused(
            pauseReason: 'budget',
            message: 'Paused: Monthly mobile data budget reached',
          );
        }
      }
    }

    return const NetworkCheckResult.allowed();
  }
}
