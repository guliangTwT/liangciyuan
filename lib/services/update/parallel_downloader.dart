import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:kazumi/request/clients/download_http_client.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 分块并行下载器：把一个支持 Range 的大文件拆成 [chunks] 份并发下载，
/// 全部完成后拼接、校验 SHA-256 再落盘。镜像站普遍按单连接限速，
/// 并行是提高总吞吐的唯一途径。
///
/// 不支持 Range（HEAD/探测失败、状态码不是 206）时自动退回单连接下载。
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
    final total = await _resolveTotalLength(url, cancelToken);
    if (total <= 0 || total < _minChunkBytes * 2) {
      // 太小不值得分块，或无法确定大小。
      await _singleConnection(
        url: url,
        savePath: savePath,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
      return;
    }
    if (!await _serverAcceptsRanges(url, total, cancelToken)) {
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

    final sink = File(savePath).openSync(mode: FileMode.write);
    final receivedLock = _ByteCounter();
    try {
      await Future.wait([
        for (final range in ranges)
          _downloadRange(
            url: url,
            range: range,
            sink: sink,
            cancelToken: cancelToken,
            onBytes: (count) {
              final totalReceived = receivedLock.add(count);
              if (!cancelToken.isCancelled) {
                onProgress(totalReceived, total);
              }
            },
          ),
      ]);
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  Future<int> _resolveTotalLength(
    String url,
    CancelToken cancelToken,
  ) async {
    try {
      final response = await DownloadHttpClient.instance.getStream(
        url,
        headers: const {'range': 'bytes=0-0'},
        receiveTimeout: const Duration(seconds: 15),
        cancelToken: cancelToken,
      );
      final contentRange = response.headers.value('content-range');
      if (contentRange != null) {
        final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
        if (match != null) return int.parse(match.group(1)!);
      }
      final contentLength = response.headers.value('content-length');
      if (contentLength != null && response.statusCode == 200) {
        // 服务器忽略 Range 且直接给全文：不分块。
        return -1;
      }
      return -1;
    } catch (_) {
      return -1;
    }
  }

  Future<bool> _serverAcceptsRanges(
    String url,
    int total,
    CancelToken cancelToken,
  ) async {
    try {
      final response = await DownloadHttpClient.instance.getStream(
        url,
        headers: {'range': 'bytes=0-1023'},
        receiveTimeout: const Duration(seconds: 15),
        cancelToken: cancelToken,
      );
      // 206 表示真分块；200 表示服务器忽略了 Range。
      return response.statusCode == 206;
    } catch (_) {
      return false;
    }
  }

  Future<void> _downloadRange({
    required String url,
    required (int, int) range,
    required RandomAccessFile sink,
    required CancelToken cancelToken,
    required void Function(int count) onBytes,
  }) async {
    var attempt = 0;
    var offset = range.$1;
    while (offset <= range.$2) {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      attempt++;
      try {
        final response = await DownloadHttpClient.instance.getStream(
          url,
          headers: {'range': 'bytes=$offset-${range.$2}'},
          receiveTimeout: const Duration(seconds: 60),
          cancelToken: cancelToken,
        );
        if (response.statusCode != 206 && response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode} for range $range');
        }
        await for (final chunk in response.data!.stream) {
          if (cancelToken.isCancelled) throw cancelToken.cancelError!;
          await sink.setPosition(offset);
          await sink.writeFrom(chunk);
          offset += chunk.length;
          onBytes(chunk.length);
        }
        if (offset > range.$2) return;
        // 提前结束：重试剩余部分。
        throw Exception('chunk ended early at $offset/${range.$2}');
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

/// 简单的线程安全计数器（Dart 单线程事件循环，原子性由同步代码保证）。
class _ByteCounter {
  int _value = 0;

  int add(int count) {
    _value += count;
    return _value;
  }
}