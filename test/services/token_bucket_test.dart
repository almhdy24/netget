import 'package:flutter_test/flutter_test.dart';
import 'package:netget/services/token_bucket.dart';

void main() {
  test('TokenBucket allows immediate consumption when unlimited', () async {
    final bucket = TokenBucket(targetBytesPerSec: 0);
    expect(bucket.isUnlimited, isTrue);

    final sw = Stopwatch()..start();
    await bucket.consume(1024 * 1024);
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(50));
  });

  test('TokenBucket throttles consumption according to target rate', () async {
    // 100 KB/s
    final bucket = TokenBucket(targetBytesPerSec: 100 * 1024);
    expect(bucket.isUnlimited, isFalse);

    // Initial burst consumes starting capacity
    await bucket.consume(100 * 1024);

    final sw = Stopwatch()..start();
    // Consuming an additional 50 KB should take ~500ms
    await bucket.consume(50 * 1024);
    sw.stop();

    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(400));
    expect(sw.elapsedMilliseconds, lessThan(800));
  });
}
