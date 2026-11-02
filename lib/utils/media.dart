import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// True when [url] already points at a media resource the player can open
/// directly. Rules whose episode entries are MP4/HLS links can skip the
/// WebView round trip entirely.
bool isDirectMediaUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  final lower = uri.path.toLowerCase();
  return _hasMediaExtension(lower);
}

bool isDirectMediaPath(String value) {
  final lower = value.toLowerCase().split('?').first.split('#').first;
  return _hasMediaExtension(lower);
}

/// HLS needs a demuxer hint; MP4 must not get one or mpv may mis-detect it.
bool isHlsMediaUrl(String url) {
  final uri = Uri.tryParse(url);
  final path = uri?.path ?? url;
  return path.toLowerCase().endsWith('.m3u8');
}

bool _hasMediaExtension(String lowerPath) {
  for (final extension in const [
    '.m3u8',
    '.mp4',
    '.mkv',
    '.webm',
    '.flv',
    '.m4v',
    '.ts',
  ]) {
    if (lowerPath.endsWith(extension)) return true;
  }
  return false;
}

String decodeVideoSource(String iframeUrl) {
  final decodedUrl = Uri.decodeFull(iframeUrl);
  final regExp = RegExp(
    r'(http[s]?://.*?\.m3u8)|(http[s]?://.*?\.mp4)',
    caseSensitive: false,
  );

  final uri = Uri.parse(decodedUrl);
  final params = uri.queryParameters;

  var matchedUrl = iframeUrl;
  params.forEach((key, value) {
    if (regExp.hasMatch(value)) {
      matchedUrl = value;
      return;
    }
  });

  return Uri.encodeFull(matchedUrl);
}

int extractEpisodeNumber(String input) {
  final regExp = RegExp(r'第?(\d+)[话集]?');
  final match = regExp.firstMatch(input);

  if (match != null && match.group(1) != null) {
    return int.tryParse(match.group(1)!) ?? 0;
  }

  return 0;
}

Future<String> getPlayerTempPath() async {
  final directory = await getTemporaryDirectory();
  return directory.path;
}

String buildShadersAbsolutePath(String baseDirectory, List<String> shaders) {
  final absolutePaths = shaders.map((shader) {
    return path.join(baseDirectory, shader);
  }).toList();
  if (Platform.isWindows) {
    return absolutePaths.join(';');
  }
  return absolutePaths.join(':');
}
