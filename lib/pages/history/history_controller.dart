import 'dart:async';

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:mobx/mobx.dart';

part 'history_controller.g.dart';

/// 一次被节流的进度更新，等节流窗口结束后再落盘。
class _PendingHistoryUpdate {
  const _PendingHistoryUpdate(this.identity, this.progress, this.duration);

  final PlaybackHistoryIdentity identity;
  final Duration progress;
  final Duration duration;
}

class HistoryController = _HistoryController with _$HistoryController;

abstract class _HistoryController with Store {
  _HistoryController(this._historyRepository);

  final IHistoryRepository _historyRepository;

  @observable
  ObservableList<History> histories = ObservableList<History>();

  /// 两次落盘之间的最短间隔。
  ///
  /// 播放页每秒调一次 [updateHistory]。以前每次都写 Hive、追加进度日志、
  /// 再把**整张历史表重读**并 clear+addAll 整个 ObservableList——历史页和
  /// 「我的」页若在后台标签里会跟着每秒重建一次，磁盘也会每秒被写一次。
  ///
  /// 现在把「太频繁的中间进度」合并掉，只保证最终一致：
  /// - 同一个条目的连续更新在 [persistInterval] 内只落盘一次；
  /// - 但 [Duration.zero]（看完归零）或换集这种「语义上必须立刻生效」的
  ///   更新不受节流，直接写。
  static const persistInterval = Duration(seconds: 5);

  DateTime? _lastPersistAt;
  _PendingHistoryUpdate? _pending;
  Timer? _flushTimer;

  void init() {
    final temp = _historyRepository.getAllHistories();
    // 列表内容没变就不要 clear+addAll：那会让所有监听者重建。
    if (_sameHistories(temp)) return;
    histories.clear();
    histories.addAll(temp);
  }

  bool _sameHistories(List<History> next) {
    if (histories.length != next.length) return false;
    for (var i = 0; i < next.length; i++) {
      if (!identical(histories[i], next[i])) return false;
    }
    return true;
  }

  Future<void> updateHistory(
    PlaybackHistoryIdentity identity,
    Duration progress, {
    Duration duration = Duration.zero,
  }) async {
    final now = DateTime.now();
    final last = _lastPersistAt;
    final tooSoon =
        last != null && now.difference(last) < persistInterval;

    // 语义上必须立刻落盘的更新：看完归零（进度被重置），或换了集数。
    final mustPersistNow = progress == Duration.zero ||
        (_pending != null &&
            (_pending!.identity.episodeNumber != identity.episodeNumber ||
                _pending!.identity.pluginName != identity.pluginName ||
                _pending!.identity.bangumiItem.id != identity.bangumiItem.id));

    if (tooSoon && !mustPersistNow) {
      // 先记住最新的进度，等节流窗口结束再写一次。
      _pending = _PendingHistoryUpdate(identity, progress, duration);
      _scheduleFlush();
      return;
    }

    // 立刻落盘时要把挂起的旧进度一并作废：否则定时器/退出时的 flush
    // 会把「上一集」的进度以更新的时间戳再写一遍，历史回退到旧集。
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending = null;
    await _persist(identity, progress, duration, now);
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(persistInterval, () {
      _flushTimer = null;
      final pending = _pending;
      if (pending == null) return;
      _pending = null;
      unawaited(
        _persist(
          pending.identity,
          pending.progress,
          pending.duration,
          DateTime.now(),
        ),
      );
    });
  }

  Future<void> _persist(
    PlaybackHistoryIdentity identity,
    Duration progress,
    Duration duration,
    DateTime now,
  ) async {
    _lastPersistAt = now;
    await _historyRepository.updateHistory(
      identity: identity,
      progress: progress,
      duration: duration,
    );
    init();
  }

  /// 立刻把待写进度落盘（暂停、退出播放页时调用）。
  Future<void> flushPendingHistory() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    await _persist(
      pending.identity,
      pending.progress,
      pending.duration,
      DateTime.now(),
    );
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  Progress? lastWatching(
    BangumiItem bangumiItem,
    String adapterName, {
    String entryKind = HistoryEntryKind.online,
  }) {
    return _historyRepository.getLastWatchingProgress(
      bangumiItem,
      adapterName,
      entryKind: entryKind,
    );
  }

  Progress? findProgress(
    BangumiItem bangumiItem,
    String adapterName,
    int episode, {
    String entryKind = HistoryEntryKind.online,
  }) {
    return _historyRepository.findProgress(
      bangumiItem,
      adapterName,
      episode,
      entryKind: entryKind,
    );
  }

  Future<void> deleteHistory(History history) async {
    await _historyRepository.deleteHistory(history);
    init();
  }

  Future<void> clearAll() async {
    await _historyRepository.clearAllHistories();
    histories.clear();
  }
}
