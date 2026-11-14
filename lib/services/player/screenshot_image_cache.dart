import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

const screenshotThumbnailCacheWidth = 240;

/// 全屏预览的解码宽度上限。
///
/// 4K 截图（3840×2160）解码成 RGBA 后单张约 33 MB。预览页会预热相邻的
/// 3 张、PageView 还会保留邻页，很容易撞上 Flutter image cache 的
/// 100 MB 上限，低端机上表现为切图时白屏甚至 OOM。
///
/// 1080 宽对 4 倍缩放仍然够看：手机屏幕逻辑宽通常 390，最宽按 2~3 倍屏
/// 算也就 1170；桌面窗口铺满时略软，但换来的是切图不再闪。
/// 真正的原图导出走「保存图片」，不受这里影响。
const screenshotPreviewCacheWidth = 1080;

void evictScreenshotImages(Uint8List bytes) {
  final image = MemoryImage(bytes);
  unawaited(image.evict());
  unawaited(
    ResizeImage.resizeIfNeeded(
      screenshotThumbnailCacheWidth,
      null,
      image,
    ).evict(),
  );
  unawaited(
    ResizeImage.resizeIfNeeded(
      screenshotPreviewCacheWidth,
      null,
      image,
    ).evict(),
  );
}
