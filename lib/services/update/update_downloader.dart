import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:kazumi/request/clients/download_http_client.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/update/update_download_mirrors.dart';
import 'package:kazumi/services/update/parallel_downloader.dart';
import 'package:kazumi/services/update/update_download_source.dart';
import 'package:kazumi/utils/crypto.dart';

String getUpdateDownloadUrlFromAsset(
  Map<String, dynamic>? asset,
  UpdateDownloadSource source,
) {
  final url =
      asset?[switch (source) {
        UpdateDownloadSource.mirror => 'mirror_download_url',
        UpdateDownloadSource.github => 'browser_download_url',
      }];
  return url is String ? url.trim() : '';
}

class UpdateIntegrityException implements Exception {
  const UpdateIntegrityException(this.expected, this.actual);

  final String expected;
  final String actual;

  @override
  String toString() => '文件完整性验证失败: 期望 $expected，实际 $actual';
}

Iterable<Object> _errorChain(Object error) sync* {
  final seen = Set<Object>.identity();
  Object? current = error;
  while (current != null && seen.add(current)) {
    yield current;
    current = switch (current) {
      NetworkException() => current.rawError,
      DioException() => current.error,
      _ => null,
    };
  }
}

String describeUpdateDownloadError(Object error, StackTrace stackTrace) {
  final causes = _errorChain(error).map(
    (cause) => switch (cause) {
      DioException() =>
        'DioException(type=${cause.type.name}, '
            'status=${cause.response?.statusCode}, message=${cause.message})',
      _ => '${cause.runtimeType}: $cause',
    },
  );
  final stack = error is NetworkException
      ? error.stackTrace ?? stackTrace
      : stackTrace;
  return '${causes.join(' -> ')} | stack=$stack';
}

String getUpdateDownloadErrorMessage(Object error) {
  final causes = _errorChain(error).toList();
  final fileError = causes.whereType<FileSystemException>().firstOrNull;
  if (fileError != null) {
    final code = fileError.osError?.errorCode;
    final windows = Platform.isWindows;
    if (windows ? code == 5 : code == 1 || code == 13) {
      return '无法写入更新文件，请检查临时目录权限';
    }
    if (windows ? code == 112 || code == 39 : code == 28) {
      return '磁盘空间不足';
    }
    return '更新文件读写失败';
  }
  if (error is UpdateIntegrityException) {
    return '文件完整性验证失败，可能是网络传输错误';
  }
  final networkType = causes.whereType<NetworkException>().firstOrNull?.type;
  switch (networkType) {
    case NetworkExceptionType.connectionTimeout ||
        NetworkExceptionType.receiveTimeout ||
        NetworkExceptionType.sendTimeout:
      return '下载超时，请稍后重试';
    case NetworkExceptionType.connectionError ||
        NetworkExceptionType.badResponse ||
        NetworkExceptionType.badCertificate:
      return '网络连接错误';
    default:
      if (causes.any(
        (cause) =>
            cause is SocketException ||
            cause is HttpException ||
            cause is HandshakeException,
      )) {
        return '网络连接错误';
      }
      return '下载失败';
  }
}

/// Measures rough throughput for every candidate with a small ranged request.
///
/// 关键点是**不能等所有源**：镜像里总有一个连不上（连接超时默认 15s），
/// 用户会看到「检查更新后卡住十几秒」。这里给整轮测速一个短预算：
/// 有源测出可用速度、或预算耗尽，就立刻拿现有结果开工。
/// 探测本身也限死连接/接收超时，不会挂住。
Future<Map<String, double>> measureUpdateDownloadSpeed(
  List<String> candidates, {
  required CancelToken cancelToken,
  Duration budget = const Duration(milliseconds: 1500),
  double goodEnoughBytesPerSecond = 300 * 1024,
}) async {
  final scores = <String, double>{};
  if (candidates.isEmpty) return scores;
  final done = Completer<void>();
  var remaining = candidates.length;
  final probeTokens = <CancelToken>[];

  void finishIfDone() {
    if (!done.isCompleted) done.complete();
  }

  for (final url in candidates) {
    final token = CancelToken();
    probeTokens.add(token);
    unawaited(
      _probeUpdateSource(url, cancelToken, token).then((score) {
        scores[url] = score;
        remaining--;
        if (remaining <= 0) finishIfDone();
        // 已经有一个足够快的源，不必再等其余探测。
        if (score >= goodEnoughBytesPerSecond) finishIfDone();
      }).catchError((Object _) {
        scores[url] = 0;
        remaining--;
        if (remaining <= 0) finishIfDone();
      }),
    );
  }

  await done.future.timeout(budget, onTimeout: () {});
  // 预算到期后仍在跑的探测一律取消，避免后台占用连接。
  for (final token in probeTokens) {
    if (!token.isCancelled) token.cancel();
  }
  return scores;
}

Future<double> _probeUpdateSource(
  String url,
  CancelToken parent,
  CancelToken token,
) async {
  if (parent.isCancelled) return 0;
  unawaited(
    parent.whenCancel.then((_) {
      if (!token.isCancelled) token.cancel();
    }),
  );
  final stopwatch = Stopwatch()..start();
  var bytes = 0;
  try {
    final response = await DownloadHttpClient.instance.getStream(
      url,
      headers: const {'range': 'bytes=0-65535'},
      connectTimeout: const Duration(seconds: 2),
      receiveTimeout: const Duration(seconds: 2),
      cancelToken: token,
    );
    await for (final chunk in response.data!.stream) {
      bytes += chunk.length;
      // 64KB 足够区分「能连」和「连不上」；再多只是空耗流量和时间。
      if (bytes >= 64 * 1024 ||
          stopwatch.elapsed > const Duration(seconds: 2)) {
        break;
      }
    }
    final elapsed = math.max(stopwatch.elapsedMilliseconds, 1);
    return bytes * 1000 / elapsed;
  } catch (_) {
    return 0;
  } finally {
    stopwatch.stop();
    if (!token.isCancelled) token.cancel();
  }
}

/// Reuses a verified cached file; otherwise downloads into a private temp
/// directory and only moves the file to [filePath] after the hash matches.
///
/// Download strategy: measure every candidate source in parallel, pick the
/// fastest, then pull the file with 8 concurrent ranged chunks (mirrors
/// throttle per-connection, so parallelism is the only way to go fast).
/// Sources without Range support fall back to a single connection.
Future<String> downloadUpdateFile({
  required String url,
  required String filePath,
  required String expectedHash,
  required CancelToken cancelToken,
  required ProgressCallback onReceiveProgress,
}) async {
  // Dio cancellation does not cover filesystem work or hashing.
  void checkCancelled() {
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;
  }

  final hash = expectedHash.toLowerCase();
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
    throw ArgumentError('更新缺少有效的 SHA256 校验值');
  }

  final file = File(filePath);
  if (await file.exists()) {
    String? localHash;
    try {
      localHash = await calculateFileHash(file);
    } catch (e) {
      KazumiLogger().w('Update: cached file verification failed', error: e);
    }
    checkCancelled();
    if (localHash == hash) {
      onReceiveProgress(1, 1);
      return filePath;
    }
    await file.delete();
  }

  checkCancelled();
  final downloadDir = await file.parent.createTemp('kazumi-update-');
  try {
    final partial = File('${downloadDir.path}/download.part');
    final candidates = updateDownloadCandidates(url);
    final scores = await measureUpdateDownloadSpeed(
      candidates,
      cancelToken: cancelToken,
    );
    checkCancelled();
    final ordered = _rankBySpeed(candidates, scores, url);
    final downloader = ParallelDownloader();
    Object? lastError;
    for (final candidate in ordered) {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      final speed = (scores[candidate] ?? 0) / 1024;
      KazumiLogger().i(
        'Update: downloading from $candidate (${speed.round()} KB/s measured)',
      );
      try {
        await downloader.download(
          url: candidate,
          savePath: partial.path,
          cancelToken: cancelToken,
          onProgress: (received, total) {
            if (!cancelToken.isCancelled) onReceiveProgress(received, total);
          },
        );
        checkCancelled();
        final downloadedHash = await calculateFileHash(partial);
        checkCancelled();
        if (downloadedHash != hash) {
          throw UpdateIntegrityException(hash, downloadedHash);
        }
        await partial.rename(filePath);
        onReceiveProgress(1, 1);
        return filePath;
      } catch (e) {
        lastError = e;
        if (cancelToken.isCancelled) rethrow;
        KazumiLogger().w(
          'Update: download source failed: $candidate',
          error: e,
        );
        if (await partial.exists()) {
          try {
            await partial.delete();
          } catch (_) {}
        }
      }
    }
    throw lastError ?? Exception('下载失败');
  } finally {
    try {
      await downloadDir.delete(recursive: true);
    } catch (e) {
      KazumiLogger().w('Update: temp download cleanup failed', error: e);
    }
  }
}

/// 速度优先排序；测速为 0 的源靠后，直连垫底（国内网络不可靠）。
List<String> _rankBySpeed(
  List<String> candidates,
  Map<String, double> scores,
  String url,
) {
  final direct = unwrapGithubMirror(url) ?? (isGithubUrl(url) ? url : null);
  return [...candidates]..sort((a, b) {
    final byScore = (scores[b] ?? 0).compareTo(scores[a] ?? 0);
    if (byScore != 0) return byScore;
    final byMirror = (a == direct ? 1 : 0).compareTo(b == direct ? 1 : 0);
    if (byMirror != 0) return byMirror;
    return candidates.indexOf(a).compareTo(candidates.indexOf(b));
  });
}
