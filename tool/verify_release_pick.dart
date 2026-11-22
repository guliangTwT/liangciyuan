// 用真实的两个发布源验证 1.0.13 的版本选择逻辑。
//
// 当前真实状态（2026-11-15）：
//   GitHub  /releases/latest -> v1.0.13
//   Codeberg/releases/latest -> v1.0.11   （1.0.12/1.0.13 因配额未公开）
//
// 旧逻辑「谁先成功用谁」可能返回 v1.0.11，导致 1.0.11~1.0.12 的用户
// 判定「已是最新」。本脚本复刻生产代码里的 raceReleases + pickHighestRelease，
// 只依赖 dart:io，可用 `dart run` 直接执行。
//
// 用法：dart run tool/verify_release_pick.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _sources = [
  'https://api.github.com/repos/guliangTwT/liangciyuan/releases/latest',
  'https://codeberg.org/api/v1/repos/GuLiang/liangciyuan/releases/latest',
];

var _failures = 0;

/// 从 pubspec.yaml 读本机版本，避免脚本里写死版本号——
/// 以前硬编码 1.0.11/1.0.12/1.0.13，发布下一个版本后必然假失败。
Future<String> _readLocalVersion() async {
  final file = File('pubspec.yaml');
  if (!await file.exists()) return '0.0.0';
  for (final line in await file.readAsLines()) {
    final match = RegExp(r'^version:\s*([0-9]+(?:\.[0-9]+)*)').firstMatch(line);
    if (match != null) return match.group(1)!;
  }
  return '0.0.0';
}

void _fail(String message) {
  _failures++;
  stderr.writeln('  x $message');
}

void _ok(String message) => stdout.writeln('  ok $message');

// ---- 以下三个函数与 lib/utils/version.dart 保持一致 ----------------------

String normalizeTag(String tag) {
  var value = tag.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final match = RegExp(r'^(\d+(?:\.\d+)*)').firstMatch(value);
  return match != null ? match.group(1)! : '';
}

bool needUpdate(String local, String remote) {
  final l = normalizeTag(local);
  final r = normalizeTag(remote);
  if (r.isEmpty) return false;
  final localParts = l.isEmpty ? const ['0'] : l.split('.');
  final remoteParts = r.split('.');
  final maxLen = localParts.length > remoteParts.length
      ? localParts.length
      : remoteParts.length;
  int seg(List<String> p, int i) =>
      i >= p.length ? 0 : (int.tryParse(p[i]) ?? 0);
  for (var i = 0; i < maxLen; i++) {
    final a = seg(localParts, i);
    final b = seg(remoteParts, i);
    if (b > a) return true;
    if (b < a) return false;
  }
  return false;
}

Map<String, dynamic> pickHighest(List<Map<String, dynamic>> available) {
  var best = available.first;
  for (final c in available.skip(1)) {
    if (needUpdate('${best['tag_name'] ?? ''}', '${c['tag_name'] ?? ''}')) {
      best = c;
    }
  }
  return best;
}

// ---- 生产代码 raceReleases 的等价实现 -----------------------------------
typedef RaceResult = ({
  List<Map<String, dynamic>?> releases,
  List<Object> errors,
});

Future<RaceResult> raceReleases(
  List<Future<Map<String, dynamic>>> queries, {
  Duration primaryGracePeriod = const Duration(milliseconds: 1200),
  bool Function(Map<String, dynamic> backupOnly)? acceptWithoutPrimary,
}) async {
  final releases = List<Map<String, dynamic>?>.filled(queries.length, null);
  final errors = <Object>[];
  final primarySettled = Completer<void>();
  final allSettled = Completer<void>();
  var pending = queries.length;
  if (queries.isEmpty) return (releases: releases, errors: errors);

  for (var i = 0; i < queries.length; i++) {
    final index = i;
    unawaited(() async {
      try {
        releases[index] = await queries[index];
      } catch (e) {
        errors.add(e);
      } finally {
        pending--;
        if (index == 0 && !primarySettled.isCompleted) primarySettled.complete();
        if (pending <= 0 && !allSettled.isCompleted) allSettled.complete();
      }
    }());
  }

  await Future.any<void>([
    primarySettled.future,
    Future<void>.delayed(primaryGracePeriod),
  ]);

  if (releases[0] == null && !allSettled.isCompleted) {
    final backupOnly = releases.whereType<Map<String, dynamic>>().toList();
    final enough = backupOnly.isNotEmpty &&
        (acceptWithoutPrimary == null || backupOnly.any(acceptWithoutPrimary));
    if (!enough) await allSettled.future;
  }
  return (releases: releases, errors: errors);
}

// ---- 验证主体 ------------------------------------------------------------

Future<Map<String, dynamic>> _fetch(HttpClient client, String url) async {
  final request = await client.getUrl(
    Uri.parse('$url?t=${DateTime.now().millisecondsSinceEpoch}'),
  );
  request.headers.set(HttpHeaders.userAgentHeader, 'liangciyuan-verify/1.0');
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
  }
  final data = json.decode(body);
  if (data is! Map) throw Exception('响应不是 JSON 对象');
  return Map<String, dynamic>.from(data);
}

Future<void> main() async {
  final localVersion = await _readLocalVersion();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);  try {
    stdout.writeln('真实双源验证（复刻生产逻辑），本机版本 $localVersion');

    // 1. 分别查询，展示两边的真实版本。
    for (final url in _sources) {
      final host = Uri.parse(url).host;
      try {
        final release = await _fetch(client, url);
        stdout.writeln('  $host -> ${release['tag_name']}');
      } catch (e) {
        stdout.writeln('  $host -> 失败：$e');
      }
    }
    stdout.writeln('');

    // 2. 跑竞速 + 版本选择。
    final raced = await raceReleases(
      [for (final url in _sources) _fetch(client, url)],
      primaryGracePeriod: const Duration(milliseconds: 1200),
      acceptWithoutPrimary: (backup) =>
          needUpdate(localVersion, '${backup['tag_name'] ?? ''}'),
    );
    final available = raced.releases.whereType<Map<String, dynamic>>().toList();
    if (available.isEmpty) {
      _fail('两个源都没返回结果：${raced.errors}');
    } else {
      final best = pickHighest(available);
      final tag = '${best['tag_name']}';
      final remote = normalizeTag(tag);
      _ok('从 ${available.length} 个可用源中选出 $tag');

      // 只有主源（GitHub）成功时才能断言「已是最新」；主源失败、
      // 后备源又停在旧版时必须报错（应用侧同样如此）。
      if (raced.releases[0] == null) {
        if (needUpdate(localVersion, tag)) {
          _ok('主源不可用，但后备源给出更高版本 $tag，可以推更新');
        } else {
          _fail('主源不可用且后备源未给出更高版本——应用会报「检查更新失败」，'
              '这正是期望行为；此处仅提示发布状态不完整');
        }
      } else if (needUpdate(localVersion, tag)) {
        _fail('本机 $localVersion 仍会被告知有更新 $tag（发布状态与本机版本不一致）');
      } else {
        _ok('本机 $localVersion 判定已是最新（$remote）');
      }

      // 逐级回退：比当前版本低的每个版本都应被提示更新。
      final segments = remote.split('.');
      if (segments.length >= 3) {
        final patch = int.tryParse(segments[2]) ?? 0;
        final older = patch > 0
            ? '${segments[0]}.${segments[1]}.${patch - 1}'
            : null;
        if (older != null) {
          if (needUpdate(older, tag)) {
            _ok('$older 用户会被提示更新到 $tag');
          } else {
            _fail('$older 用户判定「无需更新」——正是本次要修的缺陷');
          }
        }
      }

      // 3. 资产与校验值。
      final assets = (best['assets'] as List<dynamic>?) ?? const [];
      final missing =
          assets.whereType<Map>().where((a) => '${a['digest'] ?? ''}'.trim().isEmpty).length;
      final sums = assets.whereType<Map>().where((a) {
        final name = '${a['name'] ?? ''}';
        return name.toLowerCase() == 'checksums.txt';
      }).toList();
      stdout.writeln('  选中源：${assets.length} 个资产，$missing 个缺 digest，'
          'checksums.txt ${sums.isEmpty ? '缺失' : '存在'}');
      if (missing > 0 && sums.isEmpty) {
        _fail('有资产缺 digest 且没有 checksums.txt，应用会拒绝下载');
      }

      final apks = assets.whereType<Map>().where((a) {
        final n = '${a['name'] ?? ''}'.toLowerCase();
        return n.contains('android') && n.endsWith('.apk');
      }).toList();
      if (apks.isEmpty) {
        _fail('选中的发布里没有 APK');
      } else {
        _ok('有 ${apks.length} 个 APK：${apks.map((a) => a['name']).join(', ')}');
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
