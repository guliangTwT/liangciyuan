import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/update/parallel_downloader.dart';
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
      urls: ['http://127.0.0.1:${server.port}$servedPath'],
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
      urls: ['http://127.0.0.1:${server.port}$servedPath'],
      savePath: savePath,
      cancelToken: CancelToken(),
      onProgress: (received, total) {},
    );

    final downloaded = await File(savePath).readAsBytes();
    expect(downloaded, equals(data));
  });

  test(
      'starts on the first responding source instead of waiting for a dead one',
      () async {
    // 一个永远不响应的地址（模拟挂掉的镜像）+ 一个可用的本地源；
    // 必须在死源连接超时之前就开始下载。
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final rng = math.Random(7);
    final payload = List<int>.generate(2 * 1024 * 1024, (_) => rng.nextInt(256));
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range == null) {
        request.response.statusCode = 200;
        request.response.contentLength = payload.length;
        request.response.add(payload);
      } else {
        final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
        final start = int.parse(match.group(1)!);
        final end = match.group(2)!.isEmpty
            ? payload.length - 1
            : int.parse(match.group(2)!);
        request.response.statusCode = 206;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${payload.length}',
        );
        request.response.contentLength = end - start + 1;
        request.response.add(payload.sublist(start, end + 1));
      }
      await request.response.close();
    });

    final savePath = '${tempDir.path}/raced.bin';
    final stopwatch = Stopwatch()..start();
    await ParallelDownloader(chunks: 4).download(
      urls: [
        // 10.255.255.1 是不可路由地址，连接会挂起。
        'http://10.255.255.1/dead.bin',
        'http://127.0.0.1:${server.port}/ok.bin',
      ],
      savePath: savePath,
      cancelToken: CancelToken(),
      onProgress: (received, total) {},
    );
    stopwatch.stop();

    expect(await File(savePath).readAsBytes(), equals(payload));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
  });

  /// 起一个记录 Range 请求次数的本地服务，返回 (服务, 命中区间列表)。
  Future<(HttpServer, List<(int, int)>)> rangedServer(
    List<int> data, {
    String path = '/f.bin',
  }) async {
    final ranges = <(int, int)>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
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
        ranges.add((start, end));
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
    return (server, ranges);
  }

  test('大文件开满并发分块数', () async {
    // 32MB 的包，按 chunks=8 且每块至少 512KB，应该正好 8 块。
    final rng = math.Random(11);
    final data = List<int>.generate(32 * 1024 * 1024, (_) => rng.nextInt(256));
    final (server, ranges) = await rangedServer(data);

    await ParallelDownloader(chunks: 8).download(
      urls: ['http://127.0.0.1:${server.port}/f.bin'],
      savePath: '${tempDir.path}/big.bin',
      cancelToken: CancelToken(),
      onProgress: (received, total) {},
    );

    // 探测请求是 bytes=0-0，其余每个区间应该各出现一次。
    final body = ranges.where((r) => !(r.$1 == 0 && r.$2 == 0)).toList();
    expect(body.length, 8, reason: '大文件应开满 chunks 路并行');
    expect(await File('${tempDir.path}/big.bin').length(), data.length);
  });

  test('并发数被硬压上限，防止镜像用 429 拒绝', () async {
    // 实测 16 路会让 ghfast 这类镜像直接返回 429，整次下载失败。
    // 即便调用方要 32 路，也必须压回上限。
    final rng = math.Random(19);
    final data = List<int>.generate(32 * 1024 * 1024, (_) => rng.nextInt(256));
    final (server, ranges) = await rangedServer(data);

    await ParallelDownloader(chunks: 32).download(
      urls: ['http://127.0.0.1:${server.port}/f.bin'],
      savePath: '${tempDir.path}/capped.bin',
      cancelToken: CancelToken(),
      onProgress: (received, total) {},
    );

    final body = ranges.where((r) => !(r.$1 == 0 && r.$2 == 0)).toList();
    expect(
      body.length,
      lessThanOrEqualTo(8),
      reason: '并发超过 8 会触发镜像限流',
    );
    expect(await File('${tempDir.path}/capped.bin').length(), data.length);
  });

  test('小文件按块大小下限减少分块数，不硬拆成满并发', () async {
    // 4MB / 512KB = 8 块。如果文件更小，块数还要继续降。
    final rng = math.Random(13);
    final data = List<int>.generate(4 * 1024 * 1024, (_) => rng.nextInt(256));
    final (server, ranges) = await rangedServer(data);

    await ParallelDownloader(chunks: 8).download(
      urls: ['http://127.0.0.1:${server.port}/f.bin'],
      savePath: '${tempDir.path}/small.bin',
      cancelToken: CancelToken(),
      onProgress: (received, total) {},
    );

    final body = ranges.where((r) => !(r.$1 == 0 && r.$2 == 0)).toList();
    expect(body.length, 8, reason: '4MB 文件正好 8 块');
    expect(await File('${tempDir.path}/small.bin').length(), data.length);
  });

  test('2MB 文件自动降到 4 块', () async {
    final rng = math.Random(23);
    final data = List<int>.generate(2 * 1024 * 1024, (_) => rng.nextInt(256));
    final (server, ranges) = await rangedServer(data);

    await ParallelDownloader(chunks: 8).download(
      urls: ['http://127.0.0.1:${server.port}/f.bin'],
      savePath: '${tempDir.path}/tiny.bin',
      cancelToken: CancelToken(),
      onProgress: (received, total) {},
    );

    final body = ranges.where((r) => !(r.$1 == 0 && r.$2 == 0)).toList();
    expect(body.length, 4, reason: '2MB / 512KB = 4 块');
    expect(await File('${tempDir.path}/tiny.bin').length(), data.length);
  });

  test('进度回调被节流，不会每来一块数据就回调一次', () async {
    final rng = math.Random(17);
    final data = List<int>.generate(8 * 1024 * 1024, (_) => rng.nextInt(256));
    final (server, _) = await rangedServer(data);

    var callbacks = 0;
    var lastProgress = -1;
    await ParallelDownloader(chunks: 8).download(
      urls: ['http://127.0.0.1:${server.port}/f.bin'],
      savePath: '${tempDir.path}/throttled.bin',
      cancelToken: CancelToken(),
      onProgress: (received, total) {
        callbacks++;
        expect(received, greaterThanOrEqualTo(lastProgress),
            reason: '进度必须单调递增');
        lastProgress = received;
      },
    );

    // 8MB 会被切成很多次 socket 读；没有节流时回调数是几百次量级。
    expect(
      callbacks,
      lessThan(200),
      reason: '回调过多会让下载界面不停重建',
    );
expect(callbacks, greaterThan(0));
    expect(lastProgress, data.length, reason: '最终进度必须到 100%');
  });

  test('Content-Range 起点与请求不一致时换源，不会拼出错文件', () async {
    // 镜像返回 206，但 Content-Range 的起点永远是 0（缓存错位/上游改写）。
    // 以前只校验 206，这种响应会被当成「请求的那一段」拼进去，
    // 最终哈希必然不匹配且重试无效。
    final data = List<int>.generate(
      2 * 1024 * 1024,
      (i) => (i * 13 + 5) % 256,
    );
    final bad = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => bad.close(force: true));
    bad.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader) ?? '';
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
      final requestedLength = match == null
          ? data.length
          : (match.group(2)!.isEmpty
              ? data.length
              : int.parse(match.group(2)!) + 1);
      request.response.statusCode = 206;
      // 起点谎报为 0，字节数却是请求的长度。
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 0-${requestedLength - 1}/${data.length}',
      );
      request.response.contentLength = requestedLength;
      request.response.add(data.sublist(0, requestedLength));
      await request.response.close();
    });

    final good = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => good.close(force: true));
    good.listen((request) async {
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

    final savePath = '${tempDir.path}/wrong-range.bin';
    await ParallelDownloader(chunks: 4).download(
      urls: [
        'http://127.0.0.1:${bad.port}/f.bin',
        'http://127.0.0.1:${good.port}/f.bin',
      ],
      savePath: savePath,
      cancelToken: CancelToken(),
      onProgress: (received, total) {},
    );

    final downloaded = await File(savePath).readAsBytes();
    expect(
      downloaded,
      equals(data),
      reason: '起点错误的 206 必须被拒绝，改用能正确响应的源',
    );
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
