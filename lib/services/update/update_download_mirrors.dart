/// GitHub release/API acceleration prefixes. Direct access is tried and
/// compared against these mirrors before a download starts.
const List<String> githubMirrorPrefixes = [
  'https://gh-proxy.com/',
  'https://ghfast.top/',
  'https://ghproxy.net/',
  'https://gh-proxy.org/',
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
/// direct GitHub form and every mirror. Callers may reorder after measuring.
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
