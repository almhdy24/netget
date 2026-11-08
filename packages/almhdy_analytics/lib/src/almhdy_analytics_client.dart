import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'event_payload.dart';
import 'session_manager.dart';

/// Main client for AlmHdy Analytics across Flutter Android, iOS, and Desktop.
class AlmHdyAnalytics {
  static AlmHdyAnalytics? _instance;
  static AlmHdyAnalytics get instance {
    _instance ??= AlmHdyAnalytics._internal();
    return _instance!;
  }

  factory AlmHdyAnalytics() => instance;

  AlmHdyAnalytics._internal();

  String _projectKey = '';
  String _endpoint = 'https://api.almhdy24.com/api/v1/analytics/events';
  String _optOutEndpoint = 'https://api.almhdy24.com/api/v1/analytics/opt-out';
  String _appVersion = '1.0.0';
  String _platform = 'android';
  String? _platformVersion;
  String _installationId = '';
  String? _userPseudoId;
  int _batchSize = 10;
  Duration _flushInterval = const Duration(seconds: 5);
  bool _debug = false;

  final SessionManager _sessionManager = SessionManager();
  final List<AlmHdyEvent> _queue = [];
  Timer? _flushTimer;
  bool _isFlushing = false;
  bool _isOptedOut = false;
  int _backoffSeconds = 1;
  File? _bufferFile;

  static const List<String> _piiKeys = [
    'password',
    'pass',
    'secret',
    'token',
    'auth',
    'card',
    'cvv',
    'ssn',
    'phone',
    'mobile',
    'whatsapp',
    'name',
    'first_name',
    'last_name',
    'email',
  ];

  /// Initializes the analytics client. Call early in main() before runApp().
  Future<void> initialize({
    required String projectKey,
    String? endpoint,
    String? optOutEndpoint,
    String? appVersion,
    String? platform,
    String? platformVersion,
    int? batchSize,
    Duration? flushInterval,
    String? storagePath,
    bool debug = false,
  }) async {
    _projectKey = projectKey.trim();
    if (endpoint != null && endpoint.isNotEmpty) _endpoint = endpoint;
    if (optOutEndpoint != null && optOutEndpoint.isNotEmpty) {
      _optOutEndpoint = optOutEndpoint;
    }
    if (appVersion != null && appVersion.isNotEmpty) _appVersion = appVersion;
    if (platform != null && platform.isNotEmpty) {
      _platform = platform.toLowerCase();
    } else {
      _platform = _detectPlatform();
    }
    _platformVersion = platformVersion;
    if (batchSize != null) _batchSize = batchSize.clamp(1, 50);
    if (flushInterval != null) _flushInterval = flushInterval;
    _debug = debug;

    await _initStorage(storagePath);
    _startTimer();
    _log('AlmHdyAnalytics initialized for platform: $_platform');
  }

  String _detectPlatform() {
    try {
      if (Platform.isWindows) return 'windows';
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      if (Platform.isMacOS) return 'macos';
      if (Platform.isLinux) return 'linux';
    } catch (_) {}
    return 'unknown';
  }

  Future<void> _initStorage(String? customPath) async {
    try {
      final path = customPath ?? 'almhdy_analytics_buffer.json';
      _bufferFile = File(path);
      if (await _bufferFile!.exists()) {
        final content = await _bufferFile!.readAsString();
        if (content.isNotEmpty) {
          final decoded = jsonDecode(content) as Map<String, dynamic>;
          _installationId = decoded['installation_id'] as String? ?? '';
          _userPseudoId = decoded['user_pseudo_id'] as String?;
          _isOptedOut = decoded['opted_out'] as bool? ?? false;

          final savedEvents = decoded['queue'] as List<dynamic>?;
          if (savedEvents != null) {
            for (final item in savedEvents) {
              if (item is Map<String, dynamic>) {
                _queue.add(AlmHdyEvent.fromJson(item));
              }
            }
          }
        }
      }
    } catch (e) {
      _log('Failed to read offline buffer: $e');
    }

    if (_installationId.isEmpty) {
      _installationId = _generateUuid('inst_');
      await _persistState();
    }
  }

  Future<void> _persistState() async {
    if (_bufferFile == null) return;
    try {
      final map = {
        'installation_id': _installationId,
        'user_pseudo_id': _userPseudoId,
        'opted_out': _isOptedOut,
        'queue': _queue.map((e) => e.toJson()).toList(),
      };
      await _bufferFile!.writeAsString(jsonEncode(map), flush: true);
    } catch (e) {
      _log('Failed to persist offline buffer: $e');
    }
  }

  /// Checks if tracking is disabled.
  bool get isOptedOut => _isOptedOut;

  /// User opt-out from telemetry tracking.
  Future<void> optOut() async {
    _isOptedOut = true;
    _queue.clear();
    await _persistState();
    _log('User opted out of telemetry');

    try {
      final res = await http.post(
        Uri.parse(_optOutEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'X-Project-Key': _projectKey,
        },
        body: jsonEncode({
          'installation_id': _installationId,
          if (_userPseudoId != null) 'user_pseudo_id': _userPseudoId,
        }),
      );
      _log('Opt-out notified to backend (HTTP ${res.statusCode})');
    } catch (e) {
      _log('Failed to notify backend of opt-out: $e');
    }
  }

  /// Re-enable telemetry after previous opt-out.
  Future<void> optIn() async {
    _isOptedOut = false;
    await _persistState();
    _log('User opted back in to telemetry');
  }

  /// Associates subsequent events with an anonymous or pseudonymous user ID.
  void identify(String userPseudoId) {
    if (_isOptedOut) return;
    final clean = userPseudoId.trim();
    if (clean.contains('@') || RegExp(r'^[0-9+]{9,15}$').hasMatch(clean)) {
      _log('Rejected identify() string containing potential PII');
      return;
    }
    _userPseudoId = clean.length > 64 ? clean.substring(0, 64) : clean;
    _persistState();
    _log('User identified: $_userPseudoId');
  }

  /// Resets user identity and generates a new session.
  void resetUser() {
    _userPseudoId = null;
    _sessionManager.reset();
    _persistState();
    _log('User identity reset');
  }

  /// Tracks a named event with optional key-value properties.
  void track(String event, {Map<String, dynamic>? properties}) {
    if (_isOptedOut) return;
    final cleanEvent = event.trim();
    if (cleanEvent.isEmpty) return;

    final sanitizedProps = _sanitizeProperties(properties);
    final ev = AlmHdyEvent(
      event: cleanEvent.length > 64 ? cleanEvent.substring(0, 64) : cleanEvent,
      platform: _platform,
      platformVersion: _platformVersion,
      appVersion: _appVersion,
      installationId: _installationId,
      sessionId: _sessionManager.sessionId,
      userPseudoId: _userPseudoId,
      properties: sanitizedProps,
    );

    _queue.add(ev);
    _log('Enqueued event: ${ev.event} (Queue size: ${_queue.length})');

    if (_queue.length >= _batchSize) {
      flush();
    } else {
      _persistState();
    }
  }

  /// Convenience helper for recording screen transitions.
  void screenView(String screenName, {Map<String, dynamic>? properties}) {
    final props = <String, dynamic>{'screen_name': screenName};
    if (properties != null) {
      props.addAll(properties);
    }
    track('screen_view', properties: props);
  }

  /// Flushes queued events immediately to the ingestion endpoint.
  Future<void> flush() async {
    if (_isFlushing || _isOptedOut || _queue.isEmpty) return;
    _isFlushing = true;

    final batch = _queue.take(_batchSize).toList();
    final payload = {'events': batch.map((e) => e.toJson()).toList()};

    try {
      final res = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'X-Project-Key': _projectKey,
          'X-Client-Version': _appVersion,
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        _queue.removeRange(0, batch.length);
        _backoffSeconds = 1;
        _log('Flushed ${batch.length} events successfully');
        await _persistState();

        if (_queue.length >= _batchSize) {
          _isFlushing = false;
          unawaited(flush());
          return;
        }
      } else {
        _handleFailure(res.statusCode);
      }
    } catch (e) {
      _log('Network failure during flush: $e');
      _handleFailure(null);
    } finally {
      _isFlushing = false;
    }
  }

  void _handleFailure(int? statusCode) {
    _backoffSeconds = min(_backoffSeconds * 2, 60);
    _log('Backing off flush for $_backoffSeconds seconds');
  }

  Map<String, dynamic> _sanitizeProperties(Map<String, dynamic>? props) {
    if (props == null || props.isEmpty) return {};
    final clean = <String, dynamic>{};
    for (final entry in props.entries) {
      final key = entry.key.toLowerCase().trim();
      if (_piiKeys.contains(key)) continue;

      final val = entry.value;
      if (val is String) {
        clean[entry.key] = val.length > 500 ? val.substring(0, 500) : val;
      } else if (val is num || val is bool || val == null) {
        clean[entry.key] = val;
      } else if (val is List || val is Map) {
        clean[entry.key] = val;
      }
    }
    return clean;
  }

  void _startTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
  }

  static String _generateUuid(String prefix) {
    final rand = Random.secure();
    final values = List<int>.generate(16, (i) => rand.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;
    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '$prefix${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void _log(String msg) {
    if (_debug) {
      // ignore: avoid_print
      print('[AlmHdyAnalytics:Flutter] $msg');
    }
  }

  /// Disposes timers and resources.
  void dispose() {
    _flushTimer?.cancel();
  }
}
