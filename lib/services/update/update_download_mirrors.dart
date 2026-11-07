/// GitHub release/API acceleration prefixes. Direct access is tried and
/// compared against these mirrors before a download starts.
///
/// 顺序按实测首字节延迟排列（2026-11 从中国大陆测得的 TTFP）：
/// gh-proxy.org ~1.1s、gh-proxy.com ~2.4s、ghfast.top ~3.5s；
/// ghproxy.net 已长期不可用，保留在末尾仅作兜底。
const List<String> githubMirrorPrefixes = [
  'https://gh-proxy.org/',
  'https://gh-proxy.com/',
  'https://ghfast.top/',
  'https://ghproxy.net/',
];

bool isGithubUrl(String url) =>
    url.startsWith('https://github.com/') ||
    url.startsWith('https://api.github.com/');

String? unwrapGithubMirror(String url) {
  for (final prefix in githubMirrorPrefixes) {
    if (url.startsWith(prefix)) {
      final rest = url.substring(prefix.length);
      if (isGithubUrl(rest)) return rest;
    }
  }
  return null;
}

List<String> githubMirrorUrls(String url) => [
  for (final prefix in githubMirrorPrefixes) '$prefix$url',
];

/// Candidate URLs in preference order: the original URL first, then the
/// direct GitHub form and every mirror. Callers race them, so order only
/// decides ties.
List<String> updateDownloadCandidates(String url) {
  final candidates = <String>[];
  void add(String value) {
    if (value.isNotEmpty && !candidates.contains(value)) candidates.add(value);
  }

  add(url);
  final direct = unwrapGithubMirror(url) ?? (isGithubUrl(url) ? url : null);
  if (direct != null) {
    add(direct);
    for (final mirrored in githubMirrorUrls(direct)) {
      add(mirrored);
    }
  }
  return candidates;
}
