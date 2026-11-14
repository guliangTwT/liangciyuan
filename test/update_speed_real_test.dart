import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/update/parallel_downloader.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 真实网络下的更新下载吞吐实测。
///
/// 默认跳过（`SKIP_SPEEDTEST=1` 或不设置 `SPEEDTEST_URL` 时），因为它要访问
/// 外网、耗时几十秒，不适合放进常规 CI。需要手动跑：
///
/// ```
/// set SPEEDTEST_URL=<真实发布资产地址>
/// flutter test test/update_speed_real_test.dart
/// ```
///
/// 存在的意义：并行下载的收益完全取决于「镜像是否按单连接限速」这个前提。
/// 拿真实资产量一次，才知道分块数该设多少，而不是凭感觉。
void main() {
  final url = Platform.environment['SPEEDTEST_URL'] ?? '';
  final chunks = int.tryParse(
        Platform.environment['SPEEDTEST_CHUNKS'] ?? '16',
      ) ??
      16;

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('speedtest_');
    PathProviderPlatform.instance = _TestPaths(tempDir.path);
    Hive.init(tempDir.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test(
    'measure real update download throughput',
    () async {
      final savePath = '${tempDir.path}/asset.bin';
      final sw = Stopwatch()..start();
      await ParallelDownloader(chunks: chunks).download(
        urls: [url],
        savePath: savePath,
        cancelToken: CancelToken(),
        onProgress: (received, total) {},
      );
      sw.stop();

      final bytes = await File(savePath).length();
      final secs = sw.elapsedMicroseconds / 1e6;
      final speed = bytes / secs;
      // ignore: avoid_print
      print(
        'SPEEDTEST chunks=$chunks '
        'bytes=$bytes '
        'secs=${secs.toStringAsFixed(2)} '
        'Bps=${speed.toStringAsFixed(0)} '
        'MBps=${(speed / 1024 / 1024).toStringAsFixed(2)} '
        'Mbps=${(speed * 8 / 1024 / 1024).toStringAsFixed(1)}',
      );
      expect(bytes, greaterThan(0));
    },
    skip: url.isEmpty ? '未设置 SPEEDTEST_URL，跳过真实测速' : null,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}
