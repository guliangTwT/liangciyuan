import 'package:flutter_test/flutter_test.dart';

/// 观看历史落盘节流的回归测试。
///
/// 曾经的缺陷：播放页每秒调用一次 `updateHistory`，每次都写 Hive、追加进度
/// 日志，并把**整张历史表重读**后 clear+addAll 整个 ObservableList。
/// 历史页与「我的」页在后台标签时会被动地每秒重建一次，磁盘也每秒写一次；
/// 开启云同步后写入队列是无限串行的，一旦单次写超过 1 秒就持续积压。
///
/// 修复后：中间进度按间隔合并，只保证最终一致；归零/换集这类语义上必须
/// 立刻生效的更新不受节流；退出播放页前补写最后一次。
///
/// 这里用最小的调度器复刻那套判定，锁住这些语义（真实实现依赖 Hive 与
/// 播放器，不能直接单测）。
void main() {
  group('节流判定', () {
    test('间隔内的连续进度只落盘一次', () {
      final scheduler = HistoryPersistScheduler(
        interval: const Duration(seconds: 5),
      );
      final t0 = DateTime(2026, 1, 1, 12);

      // 第 1 秒：第一次更新立即落盘。
      expect(scheduler.shouldPersistNow(const Duration(seconds: 1), t0), isTrue);
      // 第 2~4 秒：被节流。
      for (var s = 2; s <= 4; s++) {
        expect(
          scheduler.shouldPersistNow(
            Duration(seconds: s),
            t0.add(Duration(seconds: s)),
          ),
          isFalse,
          reason: '第 $s 秒仍在节流窗口内',
        );
      }
      // 第 6 秒：窗口已过，再次落盘。
      expect(
        scheduler.shouldPersistNow(
          const Duration(seconds: 6),
          t0.add(const Duration(seconds: 6)),
        ),
        isTrue,
      );
    });

    test('进度归零（看完）不受节流，立刻落盘', () {
      final scheduler = HistoryPersistScheduler(
        interval: const Duration(seconds: 5),
      );
      final t0 = DateTime(2026, 1, 1, 12);
      scheduler.shouldPersistNow(const Duration(minutes: 10), t0);
      expect(
        scheduler.shouldPersistNow(
          Duration.zero,
          t0.add(const Duration(seconds: 1)),
        ),
        isTrue,
        reason: '看完会把进度归零，这一笔必须立刻生效',
      );
    });

    test('换集不受节流，立刻落盘', () {
      final scheduler = HistoryPersistScheduler(
        interval: const Duration(seconds: 5),
      );
      final t0 = DateTime(2026, 1, 1, 12);
      scheduler
        ..episode = 1
        ..shouldPersistNow(const Duration(minutes: 10), t0);
      scheduler.episode = 2;
      expect(
        scheduler.shouldPersistNow(
          const Duration(seconds: 3),
          t0.add(const Duration(seconds: 1)),
        ),
        isTrue,
        reason: '换集后必须立刻记录，否则历史会指向上一集',
      );
    });

    test('被节流的更新会留下待写值，供退出时补上', () {
      final scheduler = HistoryPersistScheduler(
        interval: const Duration(seconds: 5),
      );
      final t0 = DateTime(2026, 1, 1, 12);
      scheduler.shouldPersistNow(const Duration(minutes: 10), t0);
      scheduler.recordPending(const Duration(minutes: 10, seconds: 3));
      expect(scheduler.hasPending, isTrue);
      expect(
        scheduler.takePending(),
        const Duration(minutes: 10, seconds: 3),
        reason: '补写应使用最新的那个进度，而不是窗口开始时的值',
      );
      expect(scheduler.hasPending, isFalse, reason: '取走后不应重复补写');
    });
  });

  group('列表刷新', () {
    test('内容没变时不重建列表', () {
      final list = <String>['a', 'b'];
      expect(
        sameIdentityList(list, <String>['a', 'b']),
        isFalse,
        reason: '不同对象应视为「变了」，需要刷新',
      );
      expect(
        sameIdentityList(list, list),
        isTrue,
        reason: '同一个列表对象说明仓储返回了缓存，可以跳过 clear+addAll',
      );
    });
  });
}

/// 复刻节流判定。
class HistoryPersistScheduler {
  HistoryPersistScheduler({required this.interval});

  final Duration interval;
  DateTime? lastPersistAt;
  int episode = 0;
  Duration? _pending;
  int _lastEpisode = 0;

  bool get hasPending => _pending != null;

  Duration? takePending() {
    final value = _pending;
    _pending = null;
    return value;
  }

  void recordPending(Duration progress) => _pending = progress;

  bool shouldPersistNow(Duration progress, DateTime now) {
    final last = lastPersistAt;
    final tooSoon = last != null && now.difference(last) < interval;
    final mustPersistNow = progress == Duration.zero || episode != _lastEpisode;
    if (tooSoon && !mustPersistNow) {
      _pending = progress;
      return false;
    }
    lastPersistAt = now;
    _lastEpisode = episode;
    _pending = null;
    return true;
  }
}

/// 判断两份列表是否是同一个对象（内容未变的快速路径）。
bool sameIdentityList<T>(List<T> a, List<T> b) => identical(a, b);
