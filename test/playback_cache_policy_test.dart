import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/playback_cache_policy.dart';

/// 缓冲策略的回归测试。
///
/// 曾经的缺陷：`demuxer-max-back-bytes` 和正向预读给了同样大的 1.5 GB，
/// mpv 把已播放数据留在回看缓存里，等到必须回收时才腾空间，观感上就是
/// 「有规律地隔一阵卡一下」。加上切后台时把预读窗口清零，恢复播放还要
/// 重新缓冲，看起来更像网络问题。
///
/// 这里不启动真实播放器（需要原生库），只锁住策略自身的取值关系——
/// 那几条关系一旦被改回去，卡顿就会复现。
void main() {
  // 显式指定是否低内存，绕开 Hive 设置读取（单测环境没有初始化存储）。
  PlaybackCachePolicy policy({bool local = false, bool lowMemory = false}) =>
      PlaybackCachePolicy(
        isLocalPlayback: () => local,
        currentPlayer: () => null,
        lowMemoryOverride: () => lowMemory,
      );

  group('缓冲尺寸', () {
    test('回看缓存必须小于正向预读', () {
      final p = policy();
      expect(
        p.backBufferSize,
        lessThan(p.bufferSize),
        reason: '回看缓存不小于预读时会抢同一块预算，导致周期性回收卡顿',
      );
    });

    test('回看缓存不超过正向预读的 1/4', () {
      final p = policy();
      expect(p.backBufferSize * 4, lessThanOrEqualTo(p.bufferSize));
    });

    test('正向预读是合理量级（32MB ~ 512MB）', () {
      final p = policy();
      expect(p.bufferSize, greaterThanOrEqualTo(32 * 1024 * 1024));
      expect(p.bufferSize, lessThanOrEqualTo(512 * 1024 * 1024));
    });

    test('不会再出现 1.5GB 级别的预读', () {
      final p = policy();
      // 1.5GB = 1610612736；超过 512MB 就说明改回了旧值。
      expect(p.bufferSize, lessThan(512 * 1024 * 1024));
    });
  });

  group('预读秒数', () {
    test('cache-secs 有上限，不是「不限制」', () {
      final p = policy();
      expect(p.cacheSeconds, greaterThan(0));
      // 旧值是 36000（10 小时），等于不限制。
      expect(
        p.cacheSeconds,
        lessThan(36000),
        reason: '过大等于不限制，长时间暂停会一直下载并积压数据',
      );
    });

    test('cache-secs 不小于 60 秒', () {
      final p = policy();
      expect(p.cacheSeconds, greaterThanOrEqualTo(60));
    });
  });

  group('拖动进度条的响应速度', () {
    test('cache-pause-wait 不大于 mpv 默认的 1 秒', () {
      final p = policy();
      expect(
        p.cachePauseWaitSecs,
        lessThanOrEqualTo(1.0),
        reason: '大于默认值会让每次 seek 后恢复更慢',
      );
    });

    test('cache-pause-wait 不为 0，保留防抖余量', () {
      final p = policy();
      expect(
        p.cachePauseWaitSecs,
        greaterThan(0.0),
        reason: '0 会让缓存刚见底就恢复，紧接着又卡，来回抖',
      );
    });

    test('低内存模式下等待更久（网络慢，需要更多余量）', () {
      expect(
        policy(lowMemory: true).cachePauseWaitSecs,
        greaterThanOrEqualTo(policy().cachePauseWaitSecs),
      );
    });

    test('stream-buffer-size 放宽，抵消 MP4 的来回小 seek', () {
      final p = policy();
      // mpv 默认 128KB；放宽后才值得显式设置。
      expect(p.streamBufferBytes, greaterThan(128 * 1024));
      // 但也不该无节制，避免多占内存。
      expect(p.streamBufferBytes, lessThanOrEqualTo(4 * 1024 * 1024));
    });

    test('低内存模式不额外放大 stream buffer', () {
      expect(policy(lowMemory: true).streamBufferBytes, 0);
    });
  });

  group('低内存模式', () {
    test('低内存下预读与回看都更小，且仍满足回看更小', () {
      final p = policy(lowMemory: true);
      final normal = policy();
      expect(p.bufferSize, lessThan(normal.bufferSize));
      expect(p.backBufferSize, lessThan(normal.backBufferSize));
      expect(p.backBufferSize, lessThan(p.bufferSize));
      expect(p.cacheSeconds, lessThan(normal.cacheSeconds));
    });
  });

  group('挂起/恢复', () {
    test('没有 player 时调用挂起不会抛异常', () async {
      final p = policy();
      await p.setSuspended(true);
      await p.setSuspended(false);
    });

    test('apply 在没有 player 时安全返回', () async {
      final p = policy();
      await p.apply();
    });
  });
}
