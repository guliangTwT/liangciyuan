import 'dart:math';

/// 把 `v1.2.3` / `V1.2.3` / `1.2.3+build` 之类的 tag 归一化成可比较的数字段。
///
/// 发布 tag 用 `v` 前缀更符合 Git 习惯，但版本比较是逐段转 int 的。
/// 这里统一处理三种常见后缀，避免一次 `v1.0.5-beta` 之类的 tag 让
/// `int.parse` 抛异常、进而把整条自动更新静默关掉：
/// - 前导 `v` / `V`
/// - `+build` 元数据
/// - `-beta` / `-rc1` 等预发布后缀
String normalizeVersionTag(String tag) {
  var value = tag.trim();
  value = value.replaceFirst(RegExp(r'^[vV]'), '');
  // 只取第一个数字开头的部分，`,`, `-`, `+` 之后的都丢弃。
  final match = RegExp(r'^(\d+(?:\.\d+)*)').firstMatch(value);
  return match != null ? match.group(1)! : '';
}

/// 逐段比较，缺失的段按 0 处理。
///
/// 任何一段解析失败都按 0 处理而不是抛异常——更新检查宁可比错一次，
/// 也不能因为一个畸形版本号让用户再也收不到更新。
bool needUpdate(String localVersion, String remoteVersion) {
  final localRaw = normalizeVersionTag(localVersion);
  final remoteRaw = normalizeVersionTag(remoteVersion);
  // 远端不是有效版本号：当作没有更新，避免提示「发现新版本 」（空白版本）。
  if (remoteRaw.isEmpty) return false;
  final localVersionList = localRaw.isEmpty ? const ['0'] : localRaw.split('.');
  final remoteVersionList = remoteRaw.split('.');
  final maxLength = max(localVersionList.length, remoteVersionList.length);

  int segment(List<String> parts, int index) {
    if (index >= parts.length) return 0;
    return int.tryParse(parts[index]) ?? 0;
  }

  for (var i = 0; i < maxLength; i++) {
    final localSegment = segment(localVersionList, i);
    final remoteSegment = segment(remoteVersionList, i);
    if (remoteSegment > localSegment) {
      return true;
    } else if (remoteSegment < localSegment) {
      return false;
    }
  }
  return false;
}
