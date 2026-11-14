import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/update/auto_updater.dart';
import 'package:kazumi/utils/version.dart';

/// 双源发布的版本选择。
///
/// 背景：更新检查同时问 GitHub 与 Codeberg，原来是「谁先成功用谁」。
/// Forgejo 的 `/releases/latest` 会跳过草稿——新版本刚上传、还没点公开时，
/// Codeberg 仍返回**上一个**版本。于是网络更快的 Codeberg 先回来，
/// 应用拿 v1.0.11 去和本机的 v1.0.11 比，判定「已是最新」。
/// 结果：发布完成的 v1.0.12 永远推不到用户手里，而且没有任何报错。
///
/// 修复后不再看谁先到，而是比较两边的版本号取更高的那个。
void main() {
  Map<String, dynamic> release(String tag) => {
        'tag_name': tag,
        'assets': const [],
      };

  group('pickHighestRelease', () {
    test('后备源停在旧版本时，采用主源的新版本', () {
      final picked = pickHighestRelease([
        release('v1.0.12'), // GitHub
        release('v1.0.11'), // Codeberg（草稿未公开，latest 仍是上一版）
      ]);
      expect(picked['tag_name'], 'v1.0.12');
    });

    test('主源先返回旧版本、后备源是新版本时，采用新版本', () {
      // 反向也要成立：不能因为「主源」就无条件相信它。
      final picked = pickHighestRelease([
        release('v1.0.11'),
        release('v1.0.12'),
      ]);
      expect(picked['tag_name'], 'v1.0.12');
    });

    test('版本相同时保留主源（列表里靠前的那个）', () {
      final primary = release('v1.0.12');
      final picked = pickHighestRelease([primary, release('v1.0.12')]);
      expect(identical(picked, primary), isTrue,
          reason: '同版本应沿用主源的对象，资产地址才指向 GitHub');
    });

    test('带 v 前缀与不带前缀混用也能比较', () {
      expect(pickHighestRelease([release('1.0.9'), release('v1.0.10')])['tag_name'],
          'v1.0.10');
      expect(pickHighestRelease([release('v1.0.10'), release('1.0.9')])['tag_name'],
          'v1.0.10');
    });

    test('只有一个源可用时直接用它', () {
      expect(pickHighestRelease([release('v1.0.12')])['tag_name'], 'v1.0.12');
    });

    test('跨大版本比较（后备源领先一个次版本）', () {
      expect(pickHighestRelease([release('v1.0.99'), release('v1.1.0')])['tag_name'],
          'v1.1.0');
    });

    test('畸形 tag 不会让选择崩溃', () {
      // 任一源返回的 tag 不可解析时，不能抛异常——更新检查宁可少升一次，
      // 也不能因为一个坏 tag 让用户再也收不到更新。
      final picked = pickHighestRelease([release('nightly'), release('v1.0.12')]);
      expect(picked['tag_name'], 'v1.0.12');
      expect(
        () => pickHighestRelease([release(''), release('')]),
        returnsNormally,
      );
    });
  });

  group('与 needUpdate 的判定一致', () {
    test('选出的版本对旧版本用户必须算「需要更新」', () {
      // 这是整条链路真正的不变量：不管哪个源赢，最终都得出「有新版本」。
      final picked =
          pickHighestRelease([release('v1.0.12'), release('v1.0.11')]);
      final tag = '${picked['tag_name']}';
      expect(needUpdate('1.0.11', tag), isTrue);
      expect(needUpdate('1.0.12', tag), isFalse);
    });

    test('两个源都是旧版本时，仍然判定无需更新', () {
      // 不能因为「有两个源」就凭空造出一个更新提示。
      final picked =
          pickHighestRelease([release('v1.0.11'), release('v1.0.11')]);
      expect(needUpdate('1.0.12', '${picked['tag_name']}'), isFalse);
    });
  });
}
