import 'dart:convert';

/// Codeberg（Forgejo/Gitea）的 release API 不返回资产摘要，只给文件名、大小
/// 和下载地址。发布流程会把本次上传的所有安装包汇总成 `checksums.txt`
/// 附在同一个 release 里；应用先读它，把 SHA-256 补回每个资产，再交给
/// 下载器校验。
///
/// 文件格式与 `sha256sum` 一致，支持 `hash  name` 与 `hash *name`：
///
/// ```
/// 3f2a…  liangciyuan-3.11.0-windows-x64-setup.exe
/// ```
const List<String> checksumAssetNames = [
  'checksums.txt',
  'sha256sums.txt',
  'sha256sum.txt',
];

/// 校验值必须是完整的 64 位十六进制，其余行（注释、空行、签名行）一律忽略。
final RegExp _checksumLine = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+?)\s*$');

Map<String, String> parseChecksums(String content) {
  final sums = <String, String>{};
  for (final rawLine in const LineSplitter().convert(content)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final match = _checksumLine.firstMatch(line);
    if (match == null) continue;
    final hash = match.group(1)!.toLowerCase();
    final path = match.group(2)!.trim();
    if (path.isEmpty) continue;
    // 有些工具会写成 `dist/name` 或 `dir\name`，按文件名也能匹配上。
    sums.putIfAbsent(path, () => hash);
    sums.putIfAbsent(path.split(RegExp(r'[/\\]')).last, () => hash);
  }
  return sums;
}

/// 同一个 release 里校验文件自身的下载地址。
String? findChecksumAssetUrl(List<dynamic> assets) {
  for (final asset in assets) {
    if (asset is! Map) continue;
    final name = (asset['name'] as String?)?.trim().toLowerCase() ?? '';
    if (!checksumAssetNames.contains(name)) continue;
    final url = (asset['browser_download_url'] as String?)?.trim() ?? '';
    if (url.isNotEmpty) return url;
  }
  return null;
}

/// 把校验值写入资产的 `digest` 字段，复用下载器既有的 `sha256:<hex>` 解析。
/// 返回成功补上校验值的资产数量。
int applyChecksums(List<dynamic> assets, Map<String, String> sums) {
  var applied = 0;
  for (final asset in assets) {
    if (asset is! Map) continue;
    final name = (asset['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) continue;
    final hash = sums[name] ?? sums[name.split(RegExp(r'[/\\]')).last];
    if (hash == null) continue;
    asset['digest'] = 'sha256:$hash';
    applied++;
  }
  return applied;
}