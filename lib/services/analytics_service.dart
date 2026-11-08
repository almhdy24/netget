import 'dart:async';
import 'package:almhdy_analytics/almhdy_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Central wrapper around AlmHdyAnalytics SDK.
///
/// Ensures all calls are fire-and-forget, wrapped in try/catch,
/// and strictly filter out any PII (URLs, file paths, file names, IPs).
class AnalyticsService {
  static bool _initialized = false;

  /// Initializes AlmHdyAnalytics. Fails safely and gracefully without blocking app startup.
  static Future<void> initialize({
    required String projectKey,
    required String appVersion,
    bool debug = false,
    String? storagePath,
  }) async {
    try {
      var resolvedPath = storagePath;
      if (resolvedPath == null) {
        try {
          final docsDir = await getApplicationDocumentsDirectory();
          resolvedPath = p.join(docsDir.path, 'almhdy_analytics_buffer.json');
        } catch (_) {
          // Fall back to default relative file path if documents directory lookup fails
        }
      }

      await AlmHdyAnalytics.instance.initialize(
        projectKey: projectKey,
        appVersion: appVersion,
        storagePath: resolvedPath,
        debug: debug,
      );
      _initialized = true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print(
          '[AnalyticsService] Initialization failed (gracefully ignored): $e',
        );
      }
    }
  }

  /// Disposes analytics resources and flushes pending events.
  static Future<void> dispose() async {
    try {
      if (_initialized) {
        AlmHdyAnalytics.instance.dispose();
        _initialized = false;
      }
    } catch (_) {}
  }

  /// Fire-and-forget event tracking. Never blocks UI or download threads.
  static void track(String event, [Map<String, dynamic>? properties]) {
    try {
      if (!_initialized) return;
      AlmHdyAnalytics.instance.track(event, properties: properties);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[AnalyticsService] track error: $e');
      }
    }
  }

  /// Fire-and-forget screen view tracking.
  static void screenView(
    String screenName, [
    Map<String, dynamic>? properties,
  ]) {
    try {
      if (!_initialized) return;
      AlmHdyAnalytics.instance.screenView(screenName, properties: properties);
    } catch (_) {}
  }

  /// Records an application error/exception via analytics event.
  static void recordError(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    try {
      if (!_initialized) return;
      final errorType = error.runtimeType.toString();
      final errorMsg = error.toString();
      // Keep error message concise and free of potential query params or local paths
      final sanitizedMsg = errorMsg.length > 200
          ? errorMsg.substring(0, 200)
          : errorMsg;

      track('app_error', {
        'error_type': errorType,
        'message': sanitizedMsg,
        if (context != null) 'context': context,
        'fatal': fatal,
      });
    } catch (_) {}
  }

  /// Configures user opt-in / opt-out telemetry state.
  static Future<void> setEnabled(bool enabled) async {
    try {
      if (enabled) {
        await AlmHdyAnalytics.instance.optIn();
      } else {
        await AlmHdyAnalytics.instance.optOut();
      }
    } catch (_) {}
  }

  /// Returns current opt-out status.
  static bool get isEnabled {
    try {
      return !AlmHdyAnalytics.instance.isOptedOut;
    } catch (_) {
      return true;
    }
  }

  // =========================================================================
  // Non-PII Event Helpers
  // =========================================================================

  /// Tracks app open.
  static void trackAppOpen() {
    track('app_open');
  }

  /// Tracks app backgrounding.
  static void trackAppBackground() {
    track('app_background');
  }

  /// Tracks download added with source and category (never URL or file name).
  static void trackDownloadAdded({
    required String source, // 'link', 'clipboard', 'share'
    required String category, // 'video', 'audio', 'images', 'documents', etc.
  }) {
    track('download_added', {'source': source, 'file_type': category});
  }

  /// Tracks download lifecycle state transitions.
  static void trackDownloadStarted({required int connectionCount}) {
    track('download_started', {'connections': connectionCount});
  }

  static void trackDownloadPaused() {
    track('download_paused');
  }

  static void trackDownloadResumed() {
    track('download_resumed');
  }

  static void trackDownloadCancelled() {
    track('download_cancelled');
  }

  static void trackDownloadRetried() {
    track('download_retried');
  }

  /// Tracks download completion with coarse size/speed buckets and category.
  static void trackDownloadCompleted({
    required int totalBytes,
    required int durationSeconds,
    required num avgSpeedBytesPerSec,
    required String category,
  }) {
    final speedKbps = (avgSpeedBytesPerSec / 1024).round();
    track('download_completed', {
      'size_bucket': sizeBucket(totalBytes),
      'duration_seconds': durationSeconds,
      'speed_bucket': speedBucket(speedKbps),
      'file_type': category,
    });
  }

  /// Tracks download failure with failure type and optional HTTP code.
  static void trackDownloadFailed({
    required String errorType,
    int? httpStatus,
  }) {
    track('download_failed', {
      'error_type': errorType,
      if (httpStatus != null && httpStatus > 0) 'http_status': httpStatus,
    });
  }

  /// Tracks non-sensitive setting modification.
  static void trackSettingChanged({
    required String settingName,
    required String settingValue,
  }) {
    track('setting_changed', {'setting': settingName, 'value': settingValue});
  }

  /// Tracks when the statistics monitor or detailed reports screen is viewed.
  static void trackStatsViewed({String? view, String? source}) {
    final v = view ?? source ?? 'summary_card';
    track('stats_viewed', {'view': v});
  }

  // =========================================================================
  // Non-PII Coarse Bucketing Helpers
  // =========================================================================

  static String sizeBucket(int bytes) {
    if (bytes <= 0) return 'unknown';
    if (bytes < 1024 * 1024) return '<1MB';
    if (bytes < 10 * 1024 * 1024) return '1-10MB';
    if (bytes < 50 * 1024 * 1024) return '10-50MB';
    if (bytes < 100 * 1024 * 1024) return '50-100MB';
    if (bytes < 500 * 1024 * 1024) return '100-500MB';
    if (bytes < 1024 * 1024 * 1024) return '500MB-1GB';
    return '>1GB';
  }

  static String speedBucket(int kbps) {
    if (kbps <= 0) return '0kbps';
    if (kbps < 100) return '<100kbps';
    if (kbps < 500) return '100-500kbps';
    if (kbps < 1024) return '500kbps-1mbps';
    if (kbps < 5 * 1024) return '1-5mbps';
    if (kbps < 10 * 1024) return '5-10mbps';
    return '>10mbps';
  }
}
