import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/bangumi_image_size.dart';

/// 封面档位选择的回归测试。
///
/// 项目里几乎所有卡片都直接取 `images['large']`——那是一千多像素的原图，
/// 而网格卡片只有一百多逻辑像素宽。等于每张卡片都多下一大截数据，
/// 首页一屏二十几张卡就是十几倍的浪费，直接拖慢出图速度。
///
/// 这里锁住「按显示尺寸挑最小够用档」以及各种回退路径。
void main() {
  /// 五档齐全的字典，每档给一个可辨识的 URL。
  const full = {
    'large': 'https://img.test/large.jpg',
    'common': 'https://img.test/common.jpg',
    'medium': 'https://img.test/medium.jpg',
    'small': 'https://img.test/small.jpg',
    'grid': 'https://img.test/grid.jpg',
  };

  group('按尺寸选档', () {
    test('很小的卡片用 small，不下大图', () {
      // 40 逻辑像素 × 2 倍屏 = 80px，在 small 的 100px 以内。
      expect(
        BangumiImageSize.pick(full, logicalWidth: 40, devicePixelRatio: 2),
        full['small'],
      );
    });

    test('中等卡片用 medium', () {
      // 80 × 2 = 160px，超过 small 的 100px，但没到 medium 的 180px。
      expect(
        BangumiImageSize.pick(full, logicalWidth: 80, devicePixelRatio: 2),
        full['medium'],
      );
    });

    test('较大的卡片用 common', () {
      // 120 × 2 = 240px，超过 medium 的 180px。
      expect(
        BangumiImageSize.pick(full, logicalWidth: 120, devicePixelRatio: 2),
        full['common'],
      );
    });

    test('铺满宽度的轮播才用 large', () {
      // 400 × 2 = 800px，超过 common 的 360px。
      expect(
        BangumiImageSize.pick(full, logicalWidth: 400, devicePixelRatio: 2),
        full['large'],
      );
    });

    test('高密度屏会升级档位，避免图片发虚', () {
      final lowDpi =
          BangumiImageSize.pick(full, logicalWidth: 60, devicePixelRatio: 1);
      final highDpi =
          BangumiImageSize.pick(full, logicalWidth: 60, devicePixelRatio: 6);
      // 同样 60 逻辑像素：1 倍屏只要 60px，6 倍屏要 360px。
      expect(lowDpi, full['small']);
      expect(highDpi, full['common']);
    });

    test('绝不为小卡片选 large（档位齐全时）', () {
      // 160 逻辑像素以内 × 2 倍屏 = 320px，都不该碰原图。
      for (final width in [40.0, 80.0, 120.0, 160.0]) {
        expect(
          BangumiImageSize.pick(full, logicalWidth: width, devicePixelRatio: 2),
          isNot(full['large']),
          reason: '${width}px 宽的卡片不该下原图',
        );
      }
    });
  });

  group('缺档位时的回退', () {
    test('只有 large 时回退到 large，而不是返回空串', () {
      const onlyLarge = {'large': 'https://img.test/large.jpg'};
      expect(
        BangumiImageSize.pick(onlyLarge, logicalWidth: 60, devicePixelRatio: 2),
        onlyLarge['large'],
      );
    });

    test('缺 medium 时用 common 顶上', () {
      const noMedium = {
        'large': 'https://img.test/large.jpg',
        'common': 'https://img.test/common.jpg',
      };
      expect(
        BangumiImageSize.pick(noMedium, logicalWidth: 80, devicePixelRatio: 2),
        noMedium['common'],
      );
    });

    test('有空串时跳过空值', () {
      const blankSmall = {
        'small': '   ',
        'medium': 'https://img.test/medium.jpg',
        'large': 'https://img.test/large.jpg',
      };
      expect(
        BangumiImageSize.pick(
          blankSmall,
          logicalWidth: 50,
          devicePixelRatio: 2,
        ),
        blankSmall['medium'],
      );
    });

    test('全部为空时返回空串（按无图处理）', () {
      const empty = {'large': '', 'common': '', 'medium': ''};
      expect(
        BangumiImageSize.pick(empty, logicalWidth: 100),
        isEmpty,
      );
    });

    test('空字典不抛异常', () {
      expect(
        BangumiImageSize.pick(const {}, logicalWidth: 100),
        isEmpty,
      );
    });
  });

  group('边界', () {
    test('宽度为 0 时不崩，仍返回可用图', () {
      expect(
        BangumiImageSize.pick(full, logicalWidth: 0),
        isNotEmpty,
      );
    });

    test('像素密度小于 1 时不会选出更差的档', () {
      expect(
        BangumiImageSize.pick(full, logicalWidth: 150, devicePixelRatio: 0.5),
        isNotEmpty,
      );
    });
  });
}
