import 'package:flutter_test/flutter_test.dart';

/// 频道切换代次校验的回归测试。
///
/// 曾经的缺陷：`queryBangumiByTag` / `queryBangumiByTrend` 在 `await` 网络
/// 请求之后**无条件**把结果写进列表。用户在「日漫」的分页还没回来时切到
/// 「国漫」，日漫那份响应晚到就混进国漫列表——看起来像「切频道后内容不对」。
/// 同时 `isLoadingMore` 是两套请求共用的一个 bool，也会被旧响应覆盖。
///
/// 修复方式是在发请求时记下代次、`await` 之后比对。这里用最小的状态机
/// 复刻那段判定，锁住语义。
void main() {
  group('代次校验', () {
    test('同一代次的结果会被接受', () async {
      final channel = _ChannelState();
      final generation = channel.generation;
      final accepted = channel.applyIfCurrent(generation, ['A', 'B']);
      expect(accepted, isTrue);
      expect(channel.items, ['A', 'B']);
    });

    test('切频道后旧响应被丢弃', () async {
      final channel = _ChannelState();
      final staleGeneration = channel.generation;

      // 用户在请求在途时切到别的频道。
      channel.switchChannel();
      channel.items.clear();

      final accepted = channel.applyIfCurrent(staleGeneration, ['旧的番剧']);
      expect(accepted, isFalse, reason: '旧频道的结果必须被丢弃');
      expect(channel.items, isEmpty, reason: '不能把旧频道内容混进新频道');
    });

    test('切回来之后旧代次仍然无效', () async {
      final channel = _ChannelState();
      final first = channel.generation;
      channel.switchChannel();
      channel.switchChannel();
      // 即使两次切换回到了同一频道，代次已经不同。
      expect(
        channel.applyIfCurrent(first, ['不应出现']),
        isFalse,
        reason: '代次是单调递增的，不能按频道值回退',
      );
    });

    test('切频道会把加载态复位', () {
      final channel = _ChannelState()..loading = true;
      channel.switchChannel();
      expect(
        channel.loading,
        isFalse,
        reason: '上一页还在加载时切走，回来不该一直转圈',
      );
    });
  });
}

class _ChannelState {
  int generation = 0;
  bool loading = false;
  final List<String> items = [];

  void switchChannel() {
    generation++;
    loading = false;
  }

  /// 复刻 controller 里的 `if (generation != _channelGeneration) return;`
  bool applyIfCurrent(int requestGeneration, List<String> result) {
    if (requestGeneration != generation) return false;
    items.addAll(result);
    loading = false;
    return true;
  }
}
