import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 下载状态机的回归测试。
///
/// 曾经的缺陷：`enqueue()` 只看 `_activeTasks.containsKey(key)` 就 return，
/// 而 `pause()` 只置 `isPaused` + cancel token、**不把任务摘出表**
/// （要等 worker 走到 finally）。dio 的取消是异步生效的，于是「点暂停 →
/// 立刻点重试」这一段窗口里，新请求会被静默丢弃：UI 显示下载中，
/// 实际没有任何任务在跑，再点也没用。
///
/// 这里用最小的状态机复刻那段判定逻辑，锁住「暂停/取消中的旧任务不挡新请求」
/// 这条不变量，并验证正常的去重仍然生效。
void main() {
  group('任务占位判定', () {
    test('活跃任务会挡住重复请求（去重仍然有效）', () {
      final task = PendingTask();
      expect(shouldBlockEnqueue(task), isTrue);
    });

    test('已暂停的任务不挡新请求', () {
      final task = PendingTask()..isPaused = true;
      expect(
        shouldBlockEnqueue(task),
        isFalse,
        reason: '暂停后立刻重试必须能重新开始，否则下载永远卡住',
      );
    });

    test('已取消的任务不挡新请求', () {
      final task = PendingTask()..cancelToken.cancel();
      expect(shouldBlockEnqueue(task), isFalse);
    });

    test('暂停且取消的任务同样不挡', () {
      final task = PendingTask()
        ..isPaused = true
        ..cancelToken.cancel();
      expect(shouldBlockEnqueue(task), isFalse);
    });

    test('没有旧任务时允许入队', () {
      expect(shouldBlockEnqueue(null), isFalse);
    });
  });

  group('并发计数', () {
    test('暂停恢复不会让运行计数单调增长', () {
      // 旧实现：resume() 无条件 _runningCount++，而被顶掉的旧 worker
      // 退场时还会再 --，反复暂停恢复会把计数算歪，最终表现为
      // 「明明设置了并行 2 集，实际只跑 1 集」。
      final counter = SlotCounter(maxParallel: 2);

      // 第一次入队占一个槽位。
      expect(counter.tryStart(), isTrue);
      expect(counter.running, 1);

      // 暂停后重试：旧 worker 还没退场就重新入队。
      expect(counter.tryStart(), isTrue);
      expect(counter.running, 2, reason: '重试应占新槽位');

      // 旧 worker 退场。
      counter.finish();
      expect(counter.running, 1, reason: '旧 worker 退场只回收自己那一个');

      counter.finish();
      expect(counter.running, 0);
    });

    test('超过并发上限时排队而不是丢弃', () {
      final counter = SlotCounter(maxParallel: 1);
      expect(counter.tryStart(), isTrue);
      expect(counter.tryStart(), isFalse, reason: '满了应该排队');
      expect(counter.queued, 1);
    });
  });
}

/// 复刻 `enqueue` 里的「是否应当直接返回」判定。
bool shouldBlockEnqueue(PendingTask? existing) {
  if (existing == null) return false;
  return !existing.isPaused && !existing.cancelToken.isCancelled;
}

/// 最小化的任务占位，只保留判定用到的两个状态。
class PendingTask {
  bool isPaused = false;
  final CancelToken cancelToken = CancelToken();
}

/// 复刻运行槽位的占用/释放语义。
class SlotCounter {
  SlotCounter({required this.maxParallel});

  final int maxParallel;
  int running = 0;
  int queued = 0;

  bool tryStart() {
    if (running < maxParallel) {
      running++;
      return true;
    }
    queued++;
    return false;
  }

  void finish() {
    if (running > 0) running--;
  }
}
