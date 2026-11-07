import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/async_serial_queue.dart';

void main() {
  group('mapBounded', () {
    test('keeps input order and respects the concurrency cap', () async {
      var active = 0;
      var maxActive = 0;
      final results = await mapBounded<int, int>(
        [1, 2, 3, 4, 5, 6, 7, 8],
        (value) async {
          active++;
          if (active > maxActive) maxActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
          return value * 2;
        },
        concurrency: 3,
      );

      expect(results, [2, 4, 6, 8, 10, 12, 14, 16]);
      expect(maxActive, lessThanOrEqualTo(3));
      // 真正并发才有加速：8 项、每项 5ms、并发 3 一定远低于串行的 40ms。
      expect(maxActive, greaterThan(1));
    });

    test('stops starting new work after the first failure', () async {
      final started = <int>[];
      await expectLater(
        mapBounded<int, void>(
          [1, 2, 3, 4, 5, 6],
          (value) async {
            started.add(value);
            if (value == 2) throw StateError('boom');
            await Future<void>.delayed(const Duration(milliseconds: 5));
          },
          concurrency: 1,
        ),
        throwsStateError,
      );
      expect(started, [1, 2]);
    });

    test('handles an empty input', () async {
      expect(await mapBounded<int, int>([], (value) async => value), isEmpty);
    });
  });

  group('AsyncSerialQueue', () {
    test('runs operations one at a time in submission order', () async {
      final queue = AsyncSerialQueue();
      final order = <int>[];
      await Future.wait([
        for (var i = 0; i < 4; i++)
          queue.run(() async {
            await Future<void>.delayed(const Duration(milliseconds: 3));
            order.add(i);
          }),
      ]);
      expect(order, [0, 1, 2, 3]);
    });

    test('a failed operation does not block the next one', () async {
      final queue = AsyncSerialQueue();
      await expectLater(
        queue.run(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(await queue.run(() async => 42), 42);
    });
  });
}
