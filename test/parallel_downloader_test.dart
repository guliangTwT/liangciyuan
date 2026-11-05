import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/update/parallel_downloader.dart';
import 'package:kazumi/services/update/update_downloader.dart';
import 'package:kazumi/utils/crypto.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('parallel_dl_test_');
    final paths = _TestPaths(tempDir.path);
    PathProviderPlatform.instance = paths;
    Hive.init(tempDir.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    // Hive 的 lock 文件占用目录，先关闭再清理。
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('streamed hash matches one-shot hash', () async {
    final data = List<int>.generate(
      3 * 1024 * 1024,
      (i) => (i * 31 + 7) % 256,
    );
    final file = File('${tempDir.path}/hash-test.bin');
    await file.writeAsBytes(data);

    final streamed = await calculateFileHash(file);
    final oneShot = sha256.convert(data).toString();
    expect(streamed, oneShot);
  });

  test('downloads a file in parallel ranged chunks and verifies content',
      () async {
    // 2MB 的伪随机内容，模拟更新包。
    final rng = math.Random(42);
    final data = List<int>.generate(2 * 1024 * 1024, (_) => rng.nextInt(256));
    final servedPath = '/package.bin';

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.uri.path, servedPath);
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range == null) {
        request.response.statusCode = 200;
        request.response.contentLength = data.length;
        request.response.add(data);
      } else {
        final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
        final start = int.parse(match.group(1)!);
        final end = match.group(2)!.isEmpty
            ? data.length - 1
            : int.parse(match.group(2)!);
        request.response.statusCode = 206;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${data.length}',
        );
        request.response.contentLength = end - start + 1;
        request.response.add(data.sublist(start, end + 1));
      }
      await request.response.close();
    });

    final savePath = '${tempDir.path}/downloaded.bin';
    final downloader = ParallelDownloader(chunks: 4);
    var lastProgress = -1;
    await downloader.download(
      url: 'http://127.0.0.1:${server.port}$servedPath',
      savePath: savePath,
      cancelToken: CancelToken(),
      onProgress: (received, total) {
        expect(total, data.length);
        expect(received >= lastProgress, isTrue);
        lastProgress = received;
      },
    );

    final downloaded = await File(savePath).readAsBytes();
    expect(downloaded.length, data.length);
    expect(downloaded, equals(data));
  });

  test('falls back to single connection when ranges are unsupported',
      () async {
    final data = List<int>.generate(
      600 * 1024,
      (i) => (i * 17) % 256,
    );
    final servedPath = '/no-range.bin';

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      // 服务器永远忽略 Range，返回 200 + 全量。
      request.response.statusCode = 200;
      request.response.contentLength = data.length;
      request.response.add(data);
      await request.response.close();
    });

    final savePath = '${tempDir.path}/no-range-download.bin';
    final downloader = ParallelDownloader(chunks: 4);
    await downloader.download(
      url: 'http://127.0.0.1:${server.port}$servedPath',
      savePath: savePath,
      cancelToken: CancelToken(),
      onProgress: (received, total) {},
    );

    final downloaded = await File(savePath).readAsBytes();
    expect(downloaded, equals(data));
  });

  test('speed probing returns on budget instead of waiting for a dead source',
      () async {
    // 一个永远不响应的地址（模拟挂掉的镜像）+ 一个可用的本地源；
    // 探测必须在预算内返回，不能等连接超时。
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final payload = List<int>.filled(256 * 1024, 7);
    server.listen((request) async {
      request.response.statusCode = 206;
      request.response.headers.set('content-range', 'bytes 0-${payload.length - 1}/${payload.length}');
      request.response.contentLength = payload.length;
      request.response.add(payload);
      await request.response.close();
    });

    final stopwatch = Stopwatch()..start();
    final scores = await measureUpdateDownloadSpeed(
      [
        // 10.255.255.1 是不可路由地址，连接会挂起。
        'http://10.255.255.1/dead.bin',
        'http://127.0.0.1:${server.port}/ok.bin',
      ],
      cancelToken: CancelToken(),
      budget: const Duration(milliseconds: 800),
    );
    stopwatch.stop();

    expect(scores['http://127.0.0.1:${server.port}/ok.bin'], greaterThan(0));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
  });
}
class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}
