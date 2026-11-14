/// 按显示尺寸挑选合适的封面档位。
///
/// Bangumi 的 `images` 字典提供五档：`large`（原始大图，常见 1000px 以上）、
/// `common`（约 400px）、`medium`（约 200px）、`small`、`grid`。
///
/// 项目里几乎所有卡片都直接取 `large`，但卡片本身只有 100~200 逻辑像素宽。
/// 结果是一张 120px 的网格卡，也要下载一张 1000px 的大图——解码后还要再
/// 缩到显示尺寸。首页一屏二十几张卡，等于多下十几倍的数据量，这也是
/// 「图出来得慢」的直接原因之一。
///
/// 这里按「显示宽度 × 像素密度」算出实际需要的像素数，挑够用的最小档；
/// 请求的档位不存在时逐级回退，最终一定回退到 `large`，不会出现空图。
abstract final class BangumiImageSize {
  /// 各档位大致对应的可用宽度（像素）。
  ///
  /// 取的是保守下界：宁可稍微多下一点，也不要选了档位后卡片发虚。
  /// 注意判断用「> 阈值」，所以阈值应当理解为「该档位仍然够清晰的最大宽度」。
  static const int _commonPx = 360;
  static const int _mediumPx = 180;
  static const int _smallPx = 100;

  /// 为「逻辑宽度 [logicalWidth]、像素密度 [devicePixelRatio]」的容器
  /// 挑选合适的图片 URL。
  ///
  /// [images] 是 Bangumi 的 images 字典。返回可用档位里最小且足够清晰的那个；
  /// 所有档位都为空时返回空字符串（调用方按无图处理）。
  static String pick(
    Map<String, String> images, {
    required double logicalWidth,
    double devicePixelRatio = 1,
  }) {
    final neededPx = logicalWidth * devicePixelRatio;
    // 从最小档往上找第一个「够用」的档位。
    for (final candidate in _ascendingWhere(neededPx)) {
      final url = images[candidate]?.trim() ?? '';
      if (url.isNotEmpty) return url;
    }
    // 计算出的档位都不可用（例如只有 large）时逐级放大兜底。
    for (final candidate in const ['common', 'large', 'medium', 'small', 'grid']) {
      final url = images[candidate]?.trim() ?? '';
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  /// 按需要的像素宽度返回候选档位，从刚好够用的最小档开始。
  ///
  /// 需要超过 360px → 从 large 起（common 只到 ~400px，再大会虚）；
  /// 需要超过 180px → 从 common 起（medium 只覆盖到 180px）；
  /// 需要超过 100px → 从 medium 起；
  /// 需要 100px 以内 → 从 small 起。
  static List<String> _ascendingWhere(double neededPx) {
    if (neededPx > _commonPx) {
      return const ['large'];
    }
    if (neededPx > _mediumPx) {
      return const ['common', 'large'];
    }
    if (neededPx > _smallPx) {
      return const ['medium', 'common', 'large'];
    }
    return const ['small', 'medium', 'common', 'large'];
  }
}
