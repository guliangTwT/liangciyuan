import 'dart:async';

import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/metered_network_service.dart';
import 'package:kazumi/services/player/low_memory_mode.dart';
import 'package:kazumi/utils/async_serial_queue.dart';
import 'package:media_kit/media_kit.dart';

/// 播放器的缓冲策略。
///
/// 之前这里只设了 `demuxer-max-bytes` 与 `demuxer-max-back-bytes`，两者都给
/// 1.5 GB——回看缓存和正向预读抢同一块预算。mpv 会把已播放的数据留在回看
/// 缓存里，等到必须回收时才腾空间，于是出现了「有规律地隔一段时间卡一下」：
/// 那正是在丢弃回看数据、重新填充预读缓冲的瞬间，与网速无关。
///
/// 现在按用途分开设置：
/// - 正向预读 `demuxer-max-bytes`：决定能提前下多少，给足；
/// - 回看缓存 `demuxer-max-back-bytes`：只为拖动进度条服务，给 1/8 就够；
/// - `cache-secs`：预读最多覆盖多少秒，避免长时间暂停时无上限地下载。
class PlaybackCachePolicy {
  PlaybackCachePolicy({
    required bool Function() isLocalPlayback,
    required Player? Function() currentPlayer,
    bool Function()? lowMemoryOverride,
  })  : _isLocalPlayback = isLocalPlayback,
        _currentPlayer = currentPlayer,
        _lowMemoryOverride = lowMemoryOverride;

  /// 低内存模式（移动网络 / 用户手动开启）下的正向预读大小。
  static const int _lowMemoryForwardBytes = 32 * 1024 * 1024;

  /// 默认正向预读大小。够 1080p 提前缓冲一两分钟。
  static const int _defaultForwardBytes = 256 * 1024 * 1024;

  /// 回看缓存。只为拖进度条服务，不参与「要不要继续下载」的决策。
  /// 给得太大会挤占正向预读，于是播放中反复触发回收 → 规律性卡顿。
  static const int _lowMemoryBackBytes = 4 * 1024 * 1024;
  static const int _defaultBackBytes = 32 * 1024 * 1024;

  /// 低内存模式下允许预读的秒数。
  static const int _lowMemoryCacheSecs = 10;

  /// 默认预读秒数。36000（10 小时）实际等于不限制，
  /// 长时间暂停会让 mpv 一直下载，回来后又要处理积压数据。
  static const int _defaultCacheSecs = 600;

  /// 暂停预读时保留的最小值：不能设成 0，否则恢复后有一段时间没有数据可用。
  static const int _suspendedCacheSecs = 1;
  static const int _suspendedReadAheadSecs = 0;

  final bool Function() _isLocalPlayback;
  final Player? Function() _currentPlayer;

  /// 测试用：绕开 Hive 直接指定是否低内存。
  /// 生产代码不传，走 [LowMemoryMode] 与网络类型判断。
  final bool Function()? _lowMemoryOverride;

  final AsyncSerialQueue _writes = AsyncSerialQueue();

  StreamSubscription<void>? _settingsSubscription;

  bool get networkAutomatic =>
      LowMemoryMode.current == LowMemoryMode.auto &&
      !_isLocalPlayback() &&
      MeteredNetworkService.isMetered;

  bool get _lowMemory =>
      _lowMemoryOverride?.call() ??
      LowMemoryMode.current.isEnabled(
        isMetered: MeteredNetworkService.isMetered,
        isLocalPlayback: _isLocalPlayback(),
      );

  int get bufferSize => _lowMemory ? _lowMemoryForwardBytes : _defaultForwardBytes;

  int get backBufferSize =>
      _lowMemory ? _lowMemoryBackBytes : _defaultBackBytes;

  int get cacheSeconds => _lowMemory ? _lowMemoryCacheSecs : _defaultCacheSecs;

  void startWatching() {
    if (_settingsSubscription != null) {
      return;
    }
    _settingsSubscription = LowMemoryMode.watch().listen((_) => _onChanged());
    MeteredNetworkService.listenable.addListener(_onChanged);
  }

  void stopWatching() {
    MeteredNetworkService.listenable.removeListener(_onChanged);
    unawaited(_settingsSubscription?.cancel());
    _settingsSubscription = null;
  }

  Future<void> apply() async {
    final player = _currentPlayer();
    if (player == null) {
      return;
    }
    try {
      final pp = player.platform as NativePlayer;
      // A stale player's initialization must not block its replacement's writes.
      await pp.waitForPlayerInitialization;
      await _writes.run(() async {
        if (!identical(_currentPlayer(), player)) {
          return;
        }
        await pp.setProperty('demuxer-max-bytes', bufferSize.toString());
        await pp.setProperty(
          'demuxer-max-back-bytes',
          backBufferSize.toString(),
        );
        await pp.setProperty('cache-secs', cacheSeconds.toString());
      });
    } catch (e) {
      KazumiLogger().w(
        'PlaybackCachePolicy: failed to apply demuxer cache size',
        error: e,
      );
    }
  }

  /// 切到后台时暂停预读，回到前台再恢复。
  ///
  /// 之前这里把 `cache-secs` 设成 0、`demuxer-readahead-secs` 设成 0，
  /// 等于彻底停止预读——恢复播放后要等重新缓冲，观感上就是「回来先卡一下」。
  /// 现在只把预读压到最小（1 秒），既省流量与 CPU，又不会让恢复阶段空转。
  Future<void> setSuspended(bool suspended) async {
    final player = _currentPlayer();
    if (player == null) {
      return;
    }
    try {
      final pp = player.platform as NativePlayer;
      await pp.waitForPlayerInitialization;
      await _writes.run(() async {
        if (!identical(_currentPlayer(), player)) {
          return;
        }
        await pp.setProperty(
          'cache-secs',
          (suspended ? _suspendedCacheSecs : cacheSeconds).toString(),
        );
        await pp.setProperty(
          'demuxer-readahead-secs',
          (suspended ? _suspendedReadAheadSecs : 1).toString(),
        );
      });
    } catch (e) {
      KazumiLogger().w(
        'PlaybackCachePolicy: failed to ${suspended ? 'suspend' : 'resume'} prefetch',
        error: e,
      );
    }
  }

  void _onChanged() {
    unawaited(apply());
  }
}
