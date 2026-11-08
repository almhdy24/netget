import 'dart:math';

/// Manages analytics session lifecycle with a 30-minute inactivity timeout.
class SessionManager {
  static const Duration sessionTimeout = Duration(minutes: 30);

  String _currentSessionId;
  DateTime _lastActivity;

  SessionManager()
    : _currentSessionId = _generateSessionId(),
      _lastActivity = DateTime.now();

  String get sessionId {
    refreshSession();
    return _currentSessionId;
  }

  void refreshSession() {
    final now = DateTime.now();
    if (now.difference(_lastActivity) > sessionTimeout) {
      _currentSessionId = _generateSessionId();
    }
    _lastActivity = now;
  }

  void reset() {
    _currentSessionId = _generateSessionId();
    _lastActivity = DateTime.now();
  }

  static String _generateSessionId() {
    final rand = Random.secure();
    final values = List<int>.generate(16, (i) => rand.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; // UUIDv4 version
    values[8] = (values[8] & 0x3f) | 0x80; // UUIDv4 variant

    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'sess_${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
