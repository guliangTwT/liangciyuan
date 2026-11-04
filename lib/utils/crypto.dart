import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';
import 'package:kazumi/utils/dandan_credentials.dart';

String generateDandanSignature(String path, int timestamp) {
  final id = dandanCredentials['id']!;
  final value = dandanCredentials['value']!;
  final data = id + timestamp.toString() + path + value;
  final bytes = utf8.encode(data);
  final digest = sha256.convert(bytes);
  return base64Encode(digest.bytes);
}

String generateBangumiMirrorSearchSignature({
  required String method,
  required String path,
  required String body,
  required int timestamp,
}) {
  final id = bangumiMirrorCredentials['id']!;
  final value = bangumiMirrorCredentials['value']!;
  final bodyDigest = sha256.convert(utf8.encode(body)).toString();
  final data = id + timestamp.toString() + method + path + bodyDigest + value;
  final digest = sha256.convert(utf8.encode(data));
  return base64Encode(digest.bytes);
}

Future<String> calculateFileHash(File file) async {
  // 流式读取：更新包可达 50MB，一次 readAsBytes 会造成内存尖峰。
  // crypto 的 startChunkedConversion 接收 Sink<Digest>；摘要完成时回调一次。
  final sink = _DigestSink();
  final input = sha256.startChunkedConversion(sink);
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  if (sink.value == null) {
    throw StateError('哈希计算未产生结果');
  }
  return sink.value!;
}

/// 极简摘要 Sink：crypto 完成摘要时调用 add。
class _DigestSink implements Sink<Digest> {
  String? value;

  @override
  void add(Digest digest) {
    value = digest.toString();
  }

  @override
  void close() {}
}
