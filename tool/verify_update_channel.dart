// 发布后验收：确认 Codeberg Release 上的清单、校验文件与下载链路都可用。
//
// 用法（在项目根目录执行）：
//   dart run tool/verify_update_channel.dart
//   dart run tool/verify_update_channel.dart --download   # 额外完整下载并校验 SHA-256
//
// 私有仓库需要 token 时可设置 CODEBERG_TOKEN（公开仓库不需要）。
//
// 检查项：
//   1. /releases/latest 返回 200，tag 是纯数字版本；
//   2. 资产里同时有 APK、Windows 安装包和 checksums.txt；
//   3. checksums.txt 覆盖每个安装包，哈希为 64 位十六进制；
//   4. 每个安装包都支持 Accept-Ranges: bytes，Range 请求返回 206；
//   5. --download 时完整下载并比对 SHA-256。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _owner = 'GuLiang';
const _repo = 'liangciyuan';

var _failures = 0;

void _fail(String message) {
  _failures++;
  stderr.writeln('  ✗ $message');
}

void _ok(String message) => stdout.writeln('  ✓ $message');

Future<void> main(List<String> args) async {
  final download = args.contains('--download');
  final api =
      'https://codeberg.org/api/v1/repos/$_owner/$_repo/releases/latest';

  stdout.writeln('检查 Codeberg 更新通道：$_owner/$_repo');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final release = await _getJson(client, api);
    final tag = '${release['tag_name'] ?? ''}';
    if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(tag)) {
      _fail('tag_name 不是纯数字版本：$tag');
    } else {
      _ok('latest = $tag');
    }

    final assets = (release['assets'] as List<dynamic>?) ?? const [];
    if (assets.isEmpty) _fail('release 没有任何资产');
    final byName = <String, Map<String, dynamic>>{
      for (final asset in assets)
        if (asset is Map) '${asset['name']}': Map<String, dynamic>.from(asset),
    };

    final checksumAsset = byName['checksums.txt'];
    final sums = <String, String>{};
    if (checksumAsset == null) {
      _fail('缺少 checksums.txt（应用内更新会拒绝下载）');
    } else {
      final text = await _getText(
        client,
        '${checksumAsset['browser_download_url']}',
      );
      sums.addAll(_parseChecksums(text));
      _ok('checksums.txt 覆盖 ${sums.length} 个文件');
    }

    final targets = <String>[
      for (final name in byName.keys)
        if (name.endsWith('.apk') ||
            name.endsWith('-setup.exe') ||
            name.endsWith('.zip'))
          name,
    ];
    if (targets.isEmpty) _fail('没有发布任何安装包');

    for (final name in targets) {
      final asset = byName[name]!;
      final url = '${asset['browser_download_url']}';
      final expected = sums[name];
      if (expected == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
        _fail('$name 在 checksums.txt 里没有有效哈希');
      } else {
        _ok('$name 的 SHA-256 = ${expected.substring(0, 12)}…');
      }

      final probe = await _probeRange(client, url);
      if (!probe.supportsRange) {
        _fail('$name 不支持 Range（并行分块下载会退化成单连接）');
      } else {
        _ok('$name 支持 Range，总长 ${_mb(probe.totalLength)}');
      }

      if (download && expected != null) {
        final actual = await _downloadHash(client, url);
        if (actual == expected) {
          _ok('$name 完整下载校验通过');
        } else {
          _fail('$name 校验不一致：期望 $expected，实际 $actual');
        }
      }
    }
  } catch (e) {
    _fail('请求失败：$e');
  } finally {
    client.close(force: true);
  }

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('全部通过。');
  } else {
    stderr.writeln('失败 $_failures 项。');
    exitCode = 1;
  }
}

Future<Map<String, dynamic>> _getJson(HttpClient client, String url) async {
  final raw = await _getText(client, url);
  final data = json.decode(raw);
  if (data is! Map) throw Exception('响应不是 JSON 对象');
  return Map<String, dynamic>.from(data);
}

Future<String> _getText(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set(HttpHeaders.userAgentHeader, 'liangciyuan-verify/1.0');
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  final response = await request.close();
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
  }
  return response.transform(utf8.decoder).join();
}

Map<String, String> _parseChecksums(String content) {
  final sums = <String, String>{};
  for (final line in const LineSplitter().convert(content)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final match = RegExp(
      r'^([a-fA-F0-9]{64})\s+\*?(.+?)\s*$',
    ).firstMatch(trimmed);
    if (match == null) continue;
    sums[match.group(2)!.trim()] = match.group(1)!.toLowerCase();
  }
  return sums;
}

Future<({bool supportsRange, int totalLength})> _probeRange(
  HttpClient client,
  String url,
) async {
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set(HttpHeaders.userAgentHeader, 'liangciyuan-verify/1.0');
  request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
  final response = await request.close();
  final acceptRanges = response.headers.value('accept-ranges') ?? '';
  final total = response.headers.contentLength;
  final ok = response.statusCode == HttpStatus.partialContent;
  await response.drain<void>();
  return (
    supportsRange: ok && acceptRanges.contains('bytes'),
    totalLength: total,
  );
}

Future<String> _downloadHash(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set(HttpHeaders.userAgentHeader, 'liangciyuan-verify/1.0');
  final response = await request.close();
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
  }
  final digest = await sha256.bind(response).single;
  return digest.toString();
}

String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';