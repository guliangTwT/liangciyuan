import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/update/auto_updater.dart';
import 'package:kazumi/utils/version.dart';

/// 双源竞速的时序。
///
/// 更新检查同时问 GitHub（主源）与 Codeberg（后备源）。原来的实现是
/// 「谁先成功用谁」，而 Forgejo 的 `/releases/latest` 会跳过草稿：
/// 新版本刚上传、尚未点公开的那段时间里，Codeberg 返回的是**上一个**版本。
/// 于是网络更快的后备源先回来，应用拿 v1.0.11 与本机的 v1.0.11 比较，
/// 判定「已是最新」——已发布的 v1.0.12 再也推不到用户手里，且不报任何错。
///
/// 这里锁住的是等待策略，不涉及网络：
/// 后备源的结果只有在「它明确说有更新」时才可以先交差。
void main() {
  group('raceReleases 等待策略', () {
    test('主源先返回时立刻结束，不等后备源', () async {
      final primary = Deferred();
      final backup = Deferred(); // 永不完成，模拟极慢的后备源
      final started = DateTime.now();

      final future = raceReleases(
        [primary.future, backup.future],
        primaryGracePeriod: const Duration(seconds: 5),
      );
      primary.complete(releaseJson('v1.0.12'));

      final result = await future.timeout(const Duration(seconds: 2));
      expect(result.releases[0]?['tag_name'], 'v1.0.12');
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 2)),
        reason: '主源已成功就不该再等后备源',
      );
    });

    test('后备源先返回、说「没有新版本」时，必须继续等主源', () async {
      final primary = Deferred();
      final backup = Deferred();

      final future = raceReleases(
        [primary.future, backup.future],
        primaryGracePeriod: const Duration(milliseconds: 50),
        acceptWithoutPrimary: (r) => needUpdate('1.0.12', '${r['tag_name']}'),
      );
      // 后备源停在上一版：对本机 1.0.12 来说「没有更新」。
      backup.complete(releaseJson('v1.0.11'));

      // 宽限期过后不应收尾，而是继续等主源。
      var settledEarly = false;
      unawaited(future.then((_) => settledEarly = true));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        settledEarly,
        isFalse,
        reason: '后备源说没更新时不能提前收尾，否则用户被钉死在旧版本',
      );

      primary.complete(releaseJson('v1.0.12'));
      final result = await future;
      expect(result.releases[0]?['tag_name'], 'v1.0.12');
      final available = result.releases.whereType<Map<String, dynamic>>();
      expect(pickHighestRelease(available.toList())['tag_name'], 'v1.0.12');
    });

    test('后备源先返回、确认有新版本时，可以不等主源', () async {
      final primary = Deferred(); // 永不完成
      final backup = Deferred();

      final future = raceReleases(
        [primary.future, backup.future],
        primaryGracePeriod: const Duration(milliseconds: 30),
        acceptWithoutPrimary: (r) => needUpdate('1.0.12', '${r['tag_name']}'),
      );
      backup.complete(releaseJson('v1.0.13'));

      final result = await future.timeout(const Duration(seconds: 2));
      expect(result.releases[0], isNull, reason: '主源始终没回来');
      expect(
        result.releases[1]?['tag_name'],
        'v1.0.13',
        reason: '后备源明确报了更高的版本，可以先给用户',
      );
    });

    test('主源失败、后备源正常时用后备源', () async {
      final primary = Deferred();
      final backup = Deferred();

      final future = raceReleases(
        [primary.future, backup.future],
        primaryGracePeriod: const Duration(milliseconds: 30),
      );
      primary.fail(Exception('github down'));
      backup.complete(releaseJson('v1.0.12'));

      final result = await future.timeout(const Duration(seconds: 2));
      expect(result.releases[0], isNull);
      expect(result.releases[1]?['tag_name'], 'v1.0.12');
      expect(result.errors, hasLength(1));
    });

    test('两个源都失败时返回空结果与错误，不抛异常', () async {
      // 抛异常由调用方决定（它会转成「检查更新失败」提示），
      // raceReleases 只负责如实汇报。
      final a = Deferred();
      final b = Deferred();
      final future = raceReleases(
        [a.future, b.future],
        primaryGracePeriod: const Duration(milliseconds: 20),
      );
      a.fail(Exception('a'));
      b.fail(Exception('b'));

      final result = await future.timeout(const Duration(seconds: 2));
      expect(result.releases.whereType<Map<String, dynamic>>(), isEmpty);
      expect(result.errors, hasLength(2));
    });

    test('主源慢但最终成功时不会被误报为失败', () async {
      // 曾经的隐患：后备源先失败，宽限期一到就收尾，
      // 于是「主源只是慢一点」被当成「检查更新失败」。
      final primary = Deferred();
      final backup = Deferred();

      final future = raceReleases(
        [primary.future, backup.future],
        primaryGracePeriod: const Duration(milliseconds: 30),
      );
      backup.fail(Exception('codeberg down'));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // 宽限期早过了，主源这才回来。
      primary.complete(releaseJson('v1.0.12'));
      final result = await future.timeout(const Duration(seconds: 2));
      expect(result.releases[0]?['tag_name'], 'v1.0.12');
    });

    test('空输入不挂起', () async {
      final result = await raceReleases(const []).timeout(
        const Duration(seconds: 2),
      );
      expect(result.releases, isEmpty);
      expect(result.errors, isEmpty);
    });
  });

  group('pickHighestRelease 与等待策略合起来', () {
    test('典型的草稿期场景：GitHub v1.0.12 + Codeberg v1.0.11', () {
      // 这是 v1.0.12 发布时的真实数据：Codeberg 那条还是 draft，
      // latest 仍指向 v1.0.11。
      final picked = pickHighestRelease([
        releaseJson('v1.0.12'),
        releaseJson('v1.0.11'),
      ]);
      expect(picked['tag_name'], 'v1.0.12');
      expect(needUpdate('1.0.11', '${picked['tag_name']}'), isTrue);
    });
  });
}

Map<String, dynamic> releaseJson(String tag) => {
      'tag_name': tag,
      'assets': const [],
    };

/// 一个可以手动控制完成时机的请求。
class Deferred {
  final Completer<Map<String, dynamic>> _completer =
      Completer<Map<String, dynamic>>();

  Future<Map<String, dynamic>> get future => _completer.future;

  void complete(Map<String, dynamic> value) => _completer.complete(value);

  void fail(Object error) => _completer.completeError(error);
}
