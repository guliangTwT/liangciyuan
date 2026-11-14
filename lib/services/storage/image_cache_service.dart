import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:kazumi/services/network/proxy_aware_image_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageCacheService {
  Stream<File> _files() async* {
    final temporary = await getTemporaryDirectory();
    final directory =
        Directory(p.join(temporary.path, DefaultCacheManager.key));
    if (!await directory.exists()) return;
    yield* directory
        .list(recursive: true, followLinks: false)
        .where((entry) => entry is File)
        .cast<File>();
  }

  Future<int> sizeInBytes() async {
    var bytes = 0;
    await for (final file in _files()) {
      // Files may expire during enumeration.
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.file) bytes += stat.size;
    }
    return bytes;
  }

  Future<void> clear() async {
    // Include orphaned files, but leave images cached after this snapshot.
    final files = await _files().toList();
    // 必须用 App 实际在用的那个 manager 清缓存。
    //
    // 这里原来是 `DefaultCacheManager()`，而图片实际由
    // [ProxyAwareImageCacheManager] 缓存——两者共用同一个 cacheKey
    // （也就共用同一个磁盘目录），但 flutter_cache_manager 的
    // JsonCacheInfoRepository 是**每个实例各自一份内存表**。
    // 用另一个实例清空，只会重写它自己那份元数据；真实实例内存里
    // 仍是旧表，下一次缓存写入会把整张旧表原样写回磁盘，导致
    // 「已清理的条目复活 + 指向已删除文件的孤儿记录」。
    await ProxyAwareImageCacheManager.instance.emptyCache();
    for (final file in files) {
      try {
        await file.delete();
      } on PathNotFoundException {
        // Already removed by the cache manager.
      }
    }
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}
