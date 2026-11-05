import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:kazumi/request/clients/download_http_client.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 分块并行下载器：把一个支持 Range 的大文件拆成 [chunks] 份并发下载。
///
/// 镜像站普遍按单连接限速，并行是提高总吞吐的唯一途径。
/// 每个分块写独立临时文件（无共享句柄、无指针竞争），一次连接内顺序
/// 追加；连接中断重试时重下该块剩余部分并继续追加到同一块文件，
/// 最终按序拼接并校验各块大小。
///
/// 不支持 Range（探测失败或状态码不是 206）时自动退回单连接下载。
class ParallelDownloader {
  ParallelDownloader({this.chunks = 8});

  /// 并发分块数。镜像普遍限制单连接 ~100-300KB/s，8 路可到 1.5MB/s+。
  final int chunks;

  static const _minChunkBytes = 512 * 1024;
  static const _maxRetriesPerChunk = 4;

  Future<void> download({
    required String url,
    required String savePath,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    // 一次探测同时回答两件事：总大小、是否支持 Range。
    // 返回 206+content-range 就说明支持，无需再发第二个探测请求
    // （多发一轮在慢镜像上会白等好几秒）。
    final total = await _resolveTotalLength(url, cancelToken);
    if (total <= 0 || total < _minChunkBytes * 2) {
      // 太小不值得分块；或服务器忽略 Range（返回 200）。
      await _singleConnection(
        url: url,
        savePath: savePath,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
      return;
    }

    final partSize = (total / chunks).ceil();
    final ranges = <(int, int)>[
      for (var i = 0; i < chunks; i++)
        (i * partSize, math.min((i + 1) * partSize - 1, total - 1)),
    ];
    // 末尾可能出现空块（partSize 向上取整时）。
    ranges.removeWhere((r) => r.$1 > r.$2);

    final partDir = await Directory.systemTemp.createTemp('kazumi-pdl-');
    try {
      final progress = _ChunkProgress(total, onProgress, cancelToken);
      final partPaths = [
        for (var i = 0; i < ranges.length; i++) '${partDir.path}/part-$i.bin',
      ];
      // eagerError：任意分块永久失败立即让整次下载失败，
      // 其余块停下，避免继续空耗带宽、进度假前进。
      await Future.wait([
        for (var i = 0; i < ranges.length; i++)
          _downloadRange(
            url: url,
            range: ranges[i],
            savePath: partPaths[i],
            cancelToken: cancelToken,
            onBytes: (chunkBytes, {reset = false}) =>
                progress.update(i, chunkBytes, reset: reset),
          ),
      ], eagerError: true);
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;

      // 校验各分块大小后按序拼接。
      final sink = File(savePath).openSync(mode: FileMode.write);
      try {
        for (var i = 0; i < ranges.length; i++) {
          final expected = ranges[i].$2 - ranges[i].$1 + 1;
          final part = File(partPaths[i]);
          if (await part.length() != expected) {
            throw Exception('分块 $i 大小不符（期望 $expected 字节）');
          }
          await for (final data in part.openRead()) {
            await sink.writeFrom(data);
          }
        }
        await sink.flush();
      } finally {
        try {
          await sink.close();
        } catch (_) {}
      }
    } finally {
      try {
        await partDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// 只需要响应头：取消订阅而不是排空。排空会把整个安装包读完，
  /// 在「不支持 Range」的服务器上等于白下一次 50MB。
  Future<void> _drain(Response<ResponseBody> response) async {
    final stream = response.data?.stream;
    if (stream == null) return;
    try {
      // listen(null).cancel() 立即释放底层连接，不消费响应体。
      await stream.listen(null).cancel();
    } catch (_) {}
  }

  Future<int> _resolveTotalLength(
    String url,
    CancelToken cancelToken,
  ) async {
    try {
      final response = await DownloadHttpClient.instance.getStream(
        url,
        headers: const {'range': 'bytes=0-0'},
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 5),
        cancelToken: cancelToken,
      );
      final contentRange = response.headers.value('content-range');
      if (response.statusCode == 206 && contentRange != null) {
        final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
        if (match != null) {
          final total = int.parse(match.group(1)!);
          await _drain(response);
          return total;
        }
      }
      // 200 或无 content-range：服务器忽略 Range，回退单连接。
      await _drain(response);
      return -1;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _downloadRange({
    required String url,
    required (int, int) range,
    required String savePath,
    required CancelToken cancelToken,
    required void Function(int chunkBytes, {bool reset}) onBytes,
  }) async {
    var attempt = 0;
    // 进度按「本块已落盘字节」汇报；重试整块重来时先回退该块计数。
    while (true) {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      attempt++;
      var reported = 0;
      onBytes(0, reset: true);
      try {
        final response = await DownloadHttpClient.instance.getStream(
          url,
          headers: {'range': 'bytes=${range.$1}-${range.$2}'},
          receiveTimeout: const Duration(seconds: 60),
          cancelToken: cancelToken,
        );
        if (response.statusCode != 206) {
          // 200 意味着服务器忽略 Range 返回全文——不能当分块数据用。
          await _drain(response);
          throw Exception(
            'range 请求返回 ${response.statusCode}，期望 206（$range）',
          );
        }
        // 每次尝试从块头重下整块并覆盖块文件；避免「已写字节与
        // offset 不同步」的追加陷阱。块只有几 MB，重下代价可接受。
        final sink = File(savePath).openSync(mode: FileMode.write);
        try {
          await for (final chunk in response.data!.stream) {
            if (cancelToken.isCancelled) throw cancelToken.cancelError!;
            await sink.writeFrom(chunk);
            reported += chunk.length;
            onBytes(chunk.length);
          }
          if (reported != range.$2 - range.$1 + 1) {
            throw Exception(
              '分块提前结束（$reported/${range.$2 - range.$1 + 1} 字节）',
            );
          }
          return;
        } finally {
          try {
            await sink.close();
          } catch (_) {}
        }
      } catch (e) {
        if (cancelToken.isCancelled) rethrow;
        if (attempt >= _maxRetriesPerChunk) rethrow;
        KazumiLogger().w(
          'ParallelDownload: range $range attempt $attempt failed, retrying',
          error: e,
        );
        await Future<void>.delayed(
          Duration(milliseconds: 500 * (1 << math.min(attempt, 4))),
        );
      }
    }
  }

  Future<void> _singleConnection({
    required String url,
    required String savePath,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    await DownloadHttpClient.instance.download(
      url,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
    );
  }
}

/// 聚合各分块已下载字节数并回调总进度。
/// 每块整块重试：重试前该块计数归零重来，总进度只按真实落盘字节计算。
class _ChunkProgress {
  _ChunkProgress(this.total, this.onProgress, this._cancelToken);

  final int total;
  final void Function(int received, int total) onProgress;
  final CancelToken _cancelToken;
  final List<int> _current = [];
  final List<int> _maxSeen = [];

  /// 进度只用「每块历史最大字节数」汇总：重试整块重来时该块当前计数
  /// 归零，但历史最大值保留，进度条因此单调递增不会倒退；
  /// 只有每块都至少完整下过一次，汇总才会到达 total。
  void update(int chunkIndex, int chunkBytes, {bool reset = false}) {
    while (_current.length <= chunkIndex) {
      _current.add(0);
      _maxSeen.add(0);
    }
    if (reset) {
      _current[chunkIndex] = 0;
    } else {
      _current[chunkIndex] += chunkBytes;
    }
    if (_current[chunkIndex] > _maxSeen[chunkIndex]) {
      _maxSeen[chunkIndex] = _current[chunkIndex];
    }
    final sum = _maxSeen.fold(0, (a, b) => a + b).clamp(0, total);
    if (!_cancelToken.isCancelled) {
      onProgress(sum, total);
    }
  }
}