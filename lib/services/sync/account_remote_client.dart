import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

/// 把账号云端存储包装成同步引擎使用的远端文件接口。
class AccountRemoteClient implements webdav.Client {
  AccountRemoteClient({required this.token});

  final String token;
  final AccountApi _api = AccountApi.instance;

  static const String _root = '/kazumiSync';

  static String kindFor(String path) {
    if (path == '$_root/collectibles.tmp') return 'collectibles';
    if (path == '$_root/collectchanges.tmp') return 'collectchanges';
    return 'p_${base64Url.encode(utf8.encode(path)).replaceAll('=', '')}';
  }

  static String? pathForKind(String kind) {
    if (kind == 'collectibles') return '$_root/collectibles.tmp';
    if (kind == 'collectchanges') return '$_root/collectchanges.tmp';
    if (!kind.startsWith('p_')) return null;
    var b64 = kind.substring(2);
    final pad = b64.length % 4;
    if (pad != 0) b64 += '=' * (4 - pad);
    try {
      return utf8.decode(base64Url.decode(b64));
    } catch (_) {
      return null;
    }
  }

  @override
  void setHeaders(Map<String, dynamic> headers) {}

  @override
  Future<void> mkdir(String path, [CancelToken? cancelToken]) async {}

  @override
  Future<void> ping([CancelToken? cancelToken]) async {
    if (!await _api.health()) {
      throw const AccountException('账号服务暂时不可用');
    }
  }

  @override
  Future<List<webdav.File>> readDir(
    String path, [
    CancelToken? cancelToken,
  ]) async {
    final items = await _api.listBlobInfos(token);
    final result = <webdav.File>[];
    for (final item in items) {
      final remote = pathForKind(item.kind);
      if (remote == null || !remote.startsWith('$path/')) continue;
      final name = remote.substring(path.length + 1);
      if (name.isEmpty || name.contains('/')) continue;
      result.add(webdav.File(name: name, isDir: false, size: item.size));
    }
    return result;
  }

  @override
  Future<void> read2File(
    String path,
    String savePath, {
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final blob = await _api.getBlob(token, kindFor(path));
    if (blob == null) {
      throw const AccountException('云端文件不存在', statusCode: 404);
    }
    await File(savePath).writeAsBytes(base64Decode(blob.payload));
  }

  @override
  Future<void> writeFromFile(
    String localFilePath,
    String path, {
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final bytes = await File(localFilePath).readAsBytes();
    await _api.putBlob(
      token,
      kindFor(path),
      base64Encode(bytes),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> remove(String path, [CancelToken? cancelToken]) async {
    await _api.deleteBlob(token, kindFor(path));
  }

  @override
  Future<void> rename(
    String oldPath,
    String newPath,
    bool overwrite, [
    CancelToken? cancelToken,
  ]) async {
    final blob = await _api.getBlob(token, kindFor(oldPath));
    if (blob == null) {
      throw const AccountException('云端文件不存在', statusCode: 404);
    }
    await _api.putBlob(
      token,
      kindFor(newPath),
      blob.payload,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _api.deleteBlob(token, kindFor(oldPath));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
