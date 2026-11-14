import 'dart:io' show HttpClientResponseCompressionState;

import 'package:ech_http/ech_http.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:kazumi/request/core/ech_transport.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/network/bangumi_image_url_rewriter.dart';
import 'package:kazumi/services/network/image_acceleration.dart';
import 'package:kazumi/services/network/image_file_response.dart';
import 'package:kazumi/utils/constants.dart' show bangumiHTTPHeader;

/// 决定一个 [http.Client] 能否共用的配置组合。
///
/// 只有代理与证书策略相同的请求才能共享连接池；换了代理就必须换客户端，
/// 否则请求还是从旧代理出去。
typedef _ClientKey = (String?, int?, bool);

class ImageFileService extends FileService {
  /// 按配置组合缓存的 HTTP 客户端。
  ///
  /// 这里原来是**每个图片请求**新建 `IOClient(createHttpClient())`，
  /// 响应体一读完就 `close()`。那等于每张封面都要重新做一次 TCP 与 TLS
  /// 握手：首页一屏几十张图，时间几乎全花在握手上；滚动时新图片也只能
  /// 等前面的连接慢慢建起来，看起来就是「图一张张挤出来」。
  ///
  /// 缓存客户端后，同一个 host 的连接和 TLS session 都可以复用。
  final _clients = <_ClientKey, http.Client>{};
  bool _closed = false;

  void close() {
    _closed = true;
    _dropClients();
  }

  /// 代理或证书策略变化后丢弃池里的连接。
  ///
  /// 客户端现在是长驻的，不像以前「用完即关」，所以换代理时必须显式
  /// 清掉，否则图片还会从旧代理出去。
  void reset() {
    if (_closed) return;
    _dropClients();
  }

  void _dropClients() {
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
  }

  http.Client _clientFor(NetworkConfig config) {
    final key = (
      config.proxyHost,
      config.proxyPort,
      config.allowBadCertificates,
    );
    return _clients.putIfAbsent(key, () {
      // 图片单独限流：一屏几十张封面全发出去会被 CDN 当异常流量，
      // TCP 慢启动也全挤在一起。8 路并行的总吞吐比不限制更高。
      return IOClient(config.createHttpClient(maxConnectionsPerHost: 8));
    });
  }

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    if (_closed) throw StateError('Image file service is closed');
    final mode = ImageAcceleration.current;
    var uri = Uri.parse(url);
    final ech =
        mode == ImageAcceleration.ech &&
        BangumiImageUrlRewriter.isBangumiImage(uri);
    if (ech) {
      uri = uri.replace(scheme: 'https');
    } else if (mode == ImageAcceleration.mirror) {
      uri = BangumiImageUrlRewriter.rewrite(uri);
    }

    final request = http.Request('GET', uri);
    final Future<http.StreamedResponse> Function(http.BaseRequest) send;
    final void Function() release;
    if (ech) {
      final lease = EchTransport.lease(uri);
      send = lease.send;
      release = lease.release;
      request.headers['user-agent'] = bangumiHTTPHeader['user-agent']!;
    } else {
      final client = _clientFor(NetworkConfig.fromSettings());
      send = client.send;
      // 连接留在池里给后面的图片复用，响应结束不做任何收尾。
      release = _keepClientAlive;
    }
    if (headers != null) request.headers.addAll(headers);

    final http.StreamedResponse response;
    try {
      response = await send(request);
    } catch (_) {
      release();
      rethrow;
    }
    return createImageFileResponse(
      response,
      // ECH preserves wire lengths after decompression; decoded size is unknown.
      contentLength:
          response is EchResponse &&
              response.compressionState ==
                  HttpClientResponseCompressionState.decompressed
          ? null
          : response.contentLength,
      onComplete: release,
    );
  }

  static void _keepClientAlive() {}
}
