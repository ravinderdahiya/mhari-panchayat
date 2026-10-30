import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mhari_panchayat/services/notification_center.dart';

void main() {
  group('NotificationCenter.pollDelay', () {
    final samples = List.generate(2000, (i) => NotificationCenter.pollDelay(Random(i)));

    test('every delay stays between 2 and 3 minutes', () {
      for (final delay in samples) {
        expect(delay, greaterThanOrEqualTo(const Duration(seconds: 120)));
        expect(delay, lessThanOrEqualTo(const Duration(seconds: 180)));
      }
    });

    test('averages about 2.5 minutes, so 10,000 phones are not polling every minute', () {
      final mean = samples.map((d) => d.inSeconds).reduce((a, b) => a + b) / samples.length;

      expect(mean, closeTo(150, 5));
    });

    test('is spread out, so phones do not all poll in the same second', () {
      final distinct = samples.map((d) => d.inSeconds).toSet();

      expect(distinct.length, greaterThan(30));
    });
  });
}
