import 'package:kazumi/request/config/api_endpoints.dart';

/// GitHub 与 Codeberg 的接口和资产地址都可能被网络阻断。这里给出同一个
/// 地址的多个取法：直连优先，其次是可用的加速前缀，最后才是仓库自己的
/// 后备域名。调用方会赛跑/依次尝试，顺序只影响优先级。
const List<String> githubMirrorPrefixes = [
  'https://gh-proxy.org/',
  'https://gh-proxy.com/',
  'https://ghfast.top/',
];

bool isGithubUrl(String url) =>
    url.startsWith('https://github.com/') ||
    url.startsWith('https://api.github.com/') ||
    url.startsWith('https://objects.githubusercontent.com/');

/// 每个 URL 的候选取法，去重后按优先级排列。
List<String> updateDownloadCandidates(String url) {
  final value = url.trim();
  if (value.isEmpty) return const [];
  final candidates = <String>[value];
  void add(String candidate) {
    if (candidate.isNotEmpty && !candidates.contains(candidate)) {
      candidates.add(candidate);
    }
  }

  if (isGithubUrl(value)) {
    for (final prefix in githubMirrorPrefixes) {
      add('$prefix$value');
    }
  } else if (value.startsWith(ApiEndpoints.projectUrl) ||
      value.startsWith('https://codeberg.org/')) {
    // Codeberg 直连不通时，GitHub 上的同名发布页是最后的退路。
    final mirrored = value.replaceFirst(
      ApiEndpoints.mirrorProjectUrl,
      ApiEndpoints.projectUrl,
    );
    add(mirrored);
  }
  return candidates;
}