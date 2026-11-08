import 'dart:math';

/// 把 `v1.2.3` / `V1.2.3` / `1.2.3` 统一成 `1.2.3`。
///
/// 发布 tag 用 `v` 前缀更符合 Git 习惯，但版本比较是逐段转 int 的，
/// 带前缀会直接抛 FormatException，所以比较前先归一化。
String normalizeVersionTag(String tag) {
  final trimmed = tag.trim();
  return trimmed.replaceFirst(RegExp(r'^[vV]'), '');
}

bool needUpdate(String localVersion, String remoteVersion) {
  final localVersionList = normalizeVersionTag(localVersion).split('.');
  final remoteVersionList = normalizeVersionTag(remoteVersion).split('.');
  final maxLength = max(localVersionList.length, remoteVersionList.length);
  for (var i = 0; i < maxLength; i++) {
    final localSegment =
        i < localVersionList.length ? int.parse(localVersionList[i]) : 0;
    final remoteSegment =
        i < remoteVersionList.length ? int.parse(remoteVersionList[i]) : 0;
    if (remoteSegment > localSegment) {
      return true;
    } else if (remoteSegment < localSegment) {
      return false;
    }
  }
  return false;
}
