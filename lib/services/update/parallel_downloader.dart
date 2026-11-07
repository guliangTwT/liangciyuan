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
/// 多源竞速：所有候选地址并发发一个 `range: bytes=0-0` 探测请求，
/// **第一个响应成功的源立即开工**，不等待其余源（镜像里总有连不上的，
/// 逐个等连接超时就是用户看到的「卡十几秒才开始」）。探测同时拿到文件
/// 总长度，因此不再额外发探测请求。慢源只作为分块失败的兜底。
class ParallelDownloader {
  ParallelDownloader({this.chunks = 8});

  /// 并发分块数。镜像普遍限制单连接 ~100-300KB/s，8 路可到 1.5MB/s+。
  final int chunks;

  static const _minChunkBytes = 512 * 1024;
  static const _maxRetriesPerChunk = 3;

  /// 所有候选都无响应时的最长等待；正常情况第一个成功响应就返回。
  static const _probeBudget = Duration(seconds: 4);

  /// 拿到第一个可用源后再多等一小会儿，收集几个备用源用于分块失败时切换。
  /// 这段时间远小于连不上的镜像的连接超时，用户感知不到。
  static const _probeGrace = Duration(milliseconds: 350);

  Future<void> download({
    required List<String> urls,
    required String savePath,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    final candidates = <String>[];
    for (final url in urls) {
      if (url.isNotEmpty && !candidates.contains(url)) candidates.add(url);
    }
    if (candidates.isEmpty) {
      throw ArgumentError('没有可用的下载地址');
    }

    final probe = await _probeCandidates(candidates, cancelToken);
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;
    if (probe == null) {
      throw Exception('所有下载源都无法连接');
    }
    if (probe.orderedUrls.isEmpty) {
      throw Exception('所有下载源都无法连接');
    }

    final total = probe.total;
    if (total <= 0 || total < _minChunkBytes * 2) {
      // 太小不值得分块；或服务器忽略 Range（返回 200）。
      await _singleConnection(
        urls: probe.orderedUrls,
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
            urls: probe.orderedUrls,
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

  /// 并发探测所有候选。**第一个支持 Range 的响应立即返回**，其余探测取消；
  /// 这样既不会等连不上的镜像，也不会因为某个源不支持 Range 就放弃分块。
  Future<_ProbeResult?> _probeCandidates(
    List<String> urls,
    CancelToken parent,
  ) async {
    final responses = <_ProbeCandidate>[];
    final done = Completer<void>();
    final tokens = <CancelToken>[];
    var pending = urls.length;
    Timer? graceTimer;

    void finishIfSettled() {
      if (done.isCompleted) return;
      // 有源支持 Range 才算真正可用。
      final hasRange = responses.any((candidate) => candidate.total > 0);
      if (hasRange) {
        // 先给其它源一个很短的窗口，凑出备用源后立刻开工。
        graceTimer ??= Timer(_probeGrace, () {
          if (!done.isCompleted) done.complete();
        });
      }
      if (pending <= 0) done.complete();
    }

    for (final url in urls) {
      final token = CancelToken();
      tokens.add(token);
      unawaited(() async {
        try {
          final candidate = await _probeOne(url, parent, token);
          if (candidate != null) {
            responses.add(candidate);
            finishIfSettled();
          }
        } finally {
          pending--;
          finishIfSettled();
        }
      }());
    }

    await done.future.timeout(_probeBudget, onTimeout: () {});
    graceTimer?.cancel();
    // 未完成的探测一律取消，不占用连接。
    for (final token in tokens) {
      if (!token.isCancelled) token.cancel();
    }
    if (responses.isEmpty) return null;

    // 支持 Range 的源排在前面（按响应速度），不支持 Range 的作兜底。
    responses.sort((a, b) {
      final byRange = (b.total > 0 ? 1 : 0).compareTo(a.total > 0 ? 1 : 0);
      if (byRange != 0) return byRange;
      return a.elapsed.compareTo(b.elapsed);
    });
    // 最快源决定是否分块；它不支持 Range 时整份文件走单连接。
    final fastest = responses.first;
    return _ProbeResult(
      total: fastest.total,
      orderedUrls: [
        fastest.url,
        for (final candidate in responses)
          if (candidate.url != fastest.url) candidate.url,
      ],
    );
  }

  /// 只取响应头：`bytes=0-0` 已能给出 206 + content-range（总长度）。
  /// 需要响应体时立刻取消订阅，避免把内容读下来。
  Future<_ProbeCandidate?> _probeOne(
    String url,
    CancelToken parent,
    CancelToken token,
  ) async {
    if (parent.isCancelled) return null;
    unawaited(
      parent.whenCancel.then((_) {
        if (!token.isCancelled) token.cancel();
      }),
    );
    final stopwatch = Stopwatch()..start();
    try {
      final response = await DownloadHttpClient.instance.getStream(
        url,
        headers: const {'range': 'bytes=0-0'},
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
        cancelToken: token,
      );
      stopwatch.stop();
      final contentRange = response.headers.value('content-range');
      await _drain(response);
      final supportsRange =
          response.statusCode == 206 && contentRange != null;
      final match =
          contentRange == null ? null : RegExp(r'/(\d+)$').firstMatch(contentRange);
      final total = match == null ? -1 : int.tryParse(match.group(1)!) ?? -1;
      return _ProbeCandidate(
        url: url,
        total: supportsRange ? total : -1,
        elapsed: stopwatch.elapsedMilliseconds,
      );
    } catch (_) {
      return null;
    } finally {
      stopwatch.stop();
      if (!token.isCancelled) token.cancel();
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

  /// 逐块下载；每个分块失败后可换下一个源继续，而不是整次下载失败。
  Future<void> _downloadRange({
    required List<String> urls,
    required (int, int) range,
    required String savePath,
    required CancelToken cancelToken,
    required void Function(int chunkBytes, {bool reset}) onBytes,
  }) async {
    final expected = range.$2 - range.$1 + 1;
    Object? lastError;
    for (final url in urls) {
      for (var attempt = 1; attempt <= _maxRetriesPerChunk; attempt++) {
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        // 进度按「本块已落盘字节」汇报；重试整块重来时先回退该块计数。
        onBytes(0, reset: true);
        try {
          await _downloadRangeOnce(
            url: url,
            range: range,
            savePath: savePath,
            cancelToken: cancelToken,
            onBytes: onBytes,
          );
          return;
        } catch (e) {
          if (cancelToken.isCancelled) rethrow;
          lastError = e;
          KazumiLogger().w(
            'ParallelDownload: $url range $range attempt $attempt failed',
            error: e,
          );
          // 已经换过源仍失败时不再叠加等待，直接下一个源。
          if (attempt < _maxRetriesPerChunk) {
            await Future<void>.delayed(
              Duration(milliseconds: 300 * attempt),
            );
          }
        }
      }
    }
    throw lastError ?? Exception('分块 ${range.$1}-${range.$2} 下载失败（$expected 字节）');
  }

  Future<void> _downloadRangeOnce({
    required String url,
    required (int, int) range,
    required String savePath,
    required CancelToken cancelToken,
    required void Function(int chunkBytes, {bool reset}) onBytes,
  }) async {
    final response = await DownloadHttpClient.instance.getStream(
      url,
      headers: {'range': 'bytes=${range.$1}-${range.$2}'},
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 30),
      cancelToken: cancelToken,
    );
    if (response.statusCode != 206) {
      // 200 意味着服务器忽略 Range 返回全文——不能当分块数据用。
      await _drain(response);
      throw Exception('range 请求返回 ${response.statusCode}，期望 206（$range）');
    }
    final expected = range.$2 - range.$1 + 1;
    var reported = 0;
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
      if (reported != expected) {
        throw Exception('分块提前结束（$reported/$expected 字节）');
      }
    } finally {
      try {
        await sink.close();
      } catch (_) {}
    }
  }

  Future<void> _singleConnection({
    required List<String> urls,
    required String savePath,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    Object? lastError;
    for (final url in urls) {
      try {
        await DownloadHttpClient.instance.download(
          url,
          savePath,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 60),
          cancelToken: cancelToken,
          onReceiveProgress: onProgress,
        );
        return;
      } catch (e) {
        if (cancelToken.isCancelled) rethrow;
        lastError = e;
        KazumiLogger().w(
          'ParallelDownload: single connection failed: $url',
          error: e,
        );
        final partial = File(savePath);
        if (await partial.exists()) {
          try {
            await partial.delete();
          } catch (_) {}
        }
      }
    }
    throw lastError ?? Exception('下载失败');
  }
}

class _ProbeCandidate {
  const _ProbeCandidate({
    required this.url,
    required this.total,
    required this.elapsed,
  });

  final String url;

  /// 支持 Range 时的文件总长度；-1 表示服务器忽略 Range。
  final int total;

  /// 从发起到拿到响应头的耗时（毫秒），用作速度排序。
  final int elapsed;
}

class _ProbeResult {
  const _ProbeResult({required this.total, required this.orderedUrls});

  final int total;

  /// 按响应速度排序后的可用源；第一个是最快源。
  final List<String> orderedUrls;
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
