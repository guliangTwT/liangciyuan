import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';

/// 弹幕时间轴与时间校准的回归测试。
///
/// 弹幕库存的是「源时间轴」时间。显示时用 `source = playback - offset`，
/// 所以发送弹幕（写入云端 + 本地回显）也必须把用户当前的播放位置换算成
/// 源时间，否则设置了时间校准后，自己刚发的弹幕会错位。
void main() {
  group('DanmakuTimeline.resolveSourceSecond', () {
    test('subtracts a positive offset', () {
      // 校准 +2 秒（弹幕比画面早 2 秒出现）：第 10 秒读取的是源第 8 秒。
      expect(
        DanmakuTimeline.resolveSourceSecond(
          const Duration(seconds: 10),
          2,
        ),
        8,
      );
    });

    test('handles a negative offset', () {
      expect(
        DanmakuTimeline.resolveSourceSecond(
          const Duration(seconds: 10),
          -2,
        ),
        12,
      );
    });

    test('returns null before the source timeline starts', () {
      expect(
        DanmakuTimeline.resolveSourceSecond(
          const Duration(seconds: 1),
          2,
        ),
        isNull,
      );
    });

    test('a danmaku sent at playback P shows up when playback is P', () {
      // 发送时按源时间写入；播放回同一位置时 resolve 出的秒数必须一致。
      const playback = Duration(seconds: 30);
      const offsetSeconds = 5.0;
      const sourceMs = 25000; // 30s - 5s
      final sourceSecond = DanmakuTimeline.resolveSourceSecond(
        playback,
        offsetSeconds,
      );
      expect(sourceSecond, sourceMs ~/ 1000);
    });
  });

  group('DanmakuTimeline.staggerDelayMilliseconds', () {
    test('spreads items across one second', () {
      expect(
        DanmakuTimeline.staggerDelayMilliseconds(index: 0, total: 4),
        0,
      );
      expect(
        DanmakuTimeline.staggerDelayMilliseconds(index: 2, total: 4),
        500,
      );
      expect(
        DanmakuTimeline.staggerDelayMilliseconds(index: 3, total: 4),
        750,
      );
    });

    test('first item has no delay so no timer is created', () {
      for (final total in [1, 2, 10, 100]) {
        expect(
          DanmakuTimeline.staggerDelayMilliseconds(index: 0, total: total),
          0,
        );
      }
    });

    test('handles an empty list without dividing by zero', () {
      expect(
        DanmakuTimeline.staggerDelayMilliseconds(index: 0, total: 0),
        0,
      );
    });
  });
}
