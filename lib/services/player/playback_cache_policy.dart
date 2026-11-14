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
  ///
  /// 4 MB 只够回看几秒，用户往回拖一点就得重新请求。64 MB 在 8 Mbps 下
  /// 约等于 64 秒的可回看范围，覆盖了绝大多数「往回拖一点重看」的操作，
  /// 而且仍只有正向预读的 1/4，不会把预读挤掉。
  static const int _lowMemoryBackBytes = 4 * 1024 * 1024;
  static const int _defaultBackBytes = 64 * 1024 * 1024;

  /// 低内存模式下允许预读的秒数。
  static const int _lowMemoryCacheSecs = 10;

  /// 默认预读秒数。36000（10 小时）实际等于不限制，
  /// 长时间暂停会让 mpv 一直下载，回来后又要处理积压数据。
  static const int _defaultCacheSecs = 600;

  /// 暂停预读时保留的最小值：不能设成 0，否则恢复后有一段时间没有数据可用。
  static const int _suspendedCacheSecs = 1;
  static const int _suspendedReadAheadSecs = 0;

  /// stream 层单次读取的块大小。mpv 默认 128 KiB。
  ///
  /// 这是 demuxer 与底层 I/O（socket）之间的缓冲，其中一半固定留给
  /// 「往回 seek」。mpv 文档明确列出放宽它能提升性能的典型场景，
  /// 第一条就是 MP4：libavformat 在解 MP4 时会来回做很多次小 seek。
  /// 128 KiB 时一半只有 64 KiB，来回 seek 很容易越过窗口重新读。
  static const int _streamBufferBytes = 1024 * 1024;

  /// libavformat 的读缓冲，mpv 默认只有 32 KiB。
  ///
  /// 这个缓冲在解码器与协议层之间，决定 libavformat 一次能拿多少数据。
  /// 32 KiB 对 HLS/分片流尤其小：一个 TS 分片动辄几百 KB，缓冲太小会让
  /// 读取被打散成很多次小请求，每次都要等一次协议层往返。放到 1 MiB
  /// 能显著减少这种碎片化读取。
  static const int _lavfBufferBytes = 1024 * 1024;

  /// 进入 buffering 后，缓存里要攒够多少秒的数据才恢复播放。
  ///
  /// mpv 默认 1 秒。注意它不是「固定等待 1 秒」，而是「要攒够 1 秒的
  /// 内容」——所以它影响的是 seek 之后的恢复时机，百兆带宽下这 1 秒内容
  /// 往往零点几秒就下完了。真正的 seek 延迟主因是下面的
  /// [_hrSeekFrameDrop]，不是这里。
  ///
  /// 这里只轻微下调，让恢复更快一点，同时保留一点余量防止「刚恢复又见底」。
  static const double _cachePauseWaitSecs = 0.5;

  /// 低内存/移动网络下的等待时间。网络本身慢，多等一点更稳。
  static const double _lowMemoryCachePauseWaitSecs = 1.0;

  /// 精确 seek 时允许解码器丢掉目标位置之前的帧。
  ///
  /// mpv 默认就是 `yes`，但 media_kit 在初始化时写死了 `no`。精确 seek 的
  /// 做法是「从上一个关键帧开始解码，一直解到目标位置」；不允许丢帧，
  /// 那段前置帧就必须全部解码完，seek 越远（关键帧间隔越大）越慢。
  /// 允许丢帧后这些帧直接跳过，是 mpv 文档里明说的加速手段。
  ///
  /// 唯一的副作用是配合去隔行滤镜之类会改时间戳的滤镜时，可能跳过目标帧；
  /// 本项目没有逐帧步进功能，也没有这类滤镜，所以这个代价不存在。
  static const bool _hrSeekFrameDrop = true;

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

  /// stream 层读块大小。低内存模式回落 mpv 默认，避免多占内存。
  int get streamBufferBytes =>
      _lowMemory ? 0 : _streamBufferBytes;

  /// libavformat 读缓冲。低内存模式回落默认 32 KiB。
  int get lavfBufferBytes => _lowMemory ? 0 : _lavfBufferBytes;

  /// 缓存填满后额外等待的秒数，见 [_cachePauseWaitSecs]。
  double get cachePauseWaitSecs =>
      _lowMemory ? _lowMemoryCachePauseWaitSecs : _cachePauseWaitSecs;

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
        // 进入 buffering 后，缓存里攒够多少秒内容才恢复播放。
        await pp.setProperty(
          'cache-pause-wait',
          cachePauseWaitSecs.toString(),
        );
        // media_kit 把这个 mpv 默认开启的加速开关关掉了，seek 越远越慢。
        await pp.setProperty(
          'hr-seek-framedrop',
          _hrSeekFrameDrop ? 'yes' : 'no',
        );
        // 0 表示交回 mpv 默认（128 KiB），只在低内存模式下走这条分支。
        final streamBuffer = streamBufferBytes;
        if (streamBuffer > 0) {
          await pp.setProperty(
            'stream-buffer-size',
            streamBuffer.toString(),
          );
        }
        // libavformat 读缓冲，默认 32 KiB，对 HLS 分片太小。
        final lavfBuffer = lavfBufferBytes;
        if (lavfBuffer > 0) {
          await pp.setProperty(
            'demuxer-lavf-buffersize',
            lavfBuffer.toString(),
          );
        }
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
