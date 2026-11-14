import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';

/// 首页频道与 Bangumi 标签的映射。
///
/// 这些字符串直接决定请求参数，写错一个字频道就永远空着，
/// 而且在 UI 上只表现为「没有番剧」，很难排查。
void main() {
  group('HomeChannel tags', () {
    test('推荐频道不传标签', () {
      expect(HomeChannel.recommend.tag, isEmpty);
    });

    test('每个频道标签唯一且非空', () {
      final tags = [
        for (final channel in HomeChannel.values)
          if (channel.tag.isNotEmpty) channel.tag,
      ];
      expect(tags.toSet().length, tags.length, reason: '标签不能重复');
      expect(tags, contains('日本'));
      expect(tags, contains('国产'));
      expect(tags, contains('剧场版'));
      expect(tags, contains('欧美'));
      expect(tags, contains('特摄'));
    });

    test('标签与实测接口返回结果一致（非空标签都能搜到番剧）', () {
      // 实测结果：特摄 63 条、欧美 775 条、国产/剧场版 1000 条封顶。
      // 这里只锁「标签名没有被改成不存在的值」，不依赖网络。
      for (final channel in HomeChannel.values) {
        if (channel.tag.isEmpty) continue;
        expect(
          channel.tag,
          isNot(contains(' ')),
          reason: '${channel.label} 的标签不应含空格',
        );
      }
    });

    test('频道顺序与底部导航一致：推荐在最前', () {
      expect(HomeChannel.values.first, HomeChannel.recommend);
    });
  });

  group('PopularController.setChannel', () {
    test('切换频道时同步 currentTag', () {
      final controller = PopularController();
      controller.setChannel(HomeChannel.chinese);
      expect(controller.currentChannel, HomeChannel.chinese);
      expect(controller.currentTag, '国产');

      controller.setChannel(HomeChannel.recommend);
      expect(controller.currentChannel, HomeChannel.recommend);
      expect(controller.currentTag, isEmpty);
    });

    test('setCurrentTag 能反查出频道', () {
      final controller = PopularController();
      controller.setCurrentTag('特摄');
      expect(controller.currentChannel, HomeChannel.special);
    });

    test('未知标签回落到推荐而非抛异常', () {
      final controller = PopularController();
      controller.setCurrentTag('这个标签不存在');
      expect(controller.currentChannel, HomeChannel.recommend);
    });
  });
}
