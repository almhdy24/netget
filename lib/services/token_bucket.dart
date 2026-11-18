import 'dart:async';
import 'dart:math';

/// High-precision token-bucket rate limiter for bandwidth shaping.
class TokenBucket {
  int targetBytesPerSec;
  double _tokens;
  DateTime _lastRefill;

  TokenBucket({this.targetBytesPerSec = 0})
    : _tokens = 0,
      _lastRefill = DateTime.now();

  bool get isUnlimited => targetBytesPerSec <= 0;

  void updateRate(int newTargetBytesPerSec) {
    targetBytesPerSec = newTargetBytesPerSec;
    if (isUnlimited) {
      _tokens = double.infinity;
    } else {
      _tokens = min(_tokens, targetBytesPerSec.toDouble());
    }
  }

  void _refill() {
    if (isUnlimited) return;
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastRefill).inMicroseconds / 1000.0;
    _lastRefill = now;

    final addedTokens = (targetBytesPerSec * elapsedMs) / 1000.0;
    final maxCapacity = targetBytesPerSec.toDouble();
    _tokens = min(maxCapacity, _tokens + addedTokens);
  }

  /// Consumes [bytes] tokens. If not enough tokens are available, delays
  /// asynchronously until sufficient tokens have refilled.
  Future<void> consume(int bytes) async {
    if (isUnlimited || bytes <= 0) return;

    _refill();
    if (_tokens >= bytes) {
      _tokens -= bytes;
      return;
    }

    final deficit = bytes - _tokens;
    _tokens = 0;
    final waitMs = ((deficit / targetBytesPerSec) * 1000.0).ceil();
    await Future<void>.delayed(Duration(milliseconds: max(5, waitMs)));
    _lastRefill = DateTime.now();
  }
}
