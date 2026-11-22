import 'dart:io';

import 'package:dio/io.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';
import 'package:kazumi/services/storage/storage.dart';

class NetworkConfig {
  const NetworkConfig({
    this.connectTimeout = const Duration(seconds: 12),
    this.receiveTimeout = const Duration(seconds: 12),
    this.sendTimeout,
    this.proxyHost,
    this.proxyPort,
    this.allowBadCertificates = false,
    this.enableLog = true,
  });

  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration? sendTimeout;
  final String? proxyHost;
  final int? proxyPort;
  final bool allowBadCertificates;
  final bool enableLog;

  bool get hasProxy => proxyHost != null && proxyPort != null;

  Uri? proxyForUri(Uri uri) {
    if (hasProxy) return Uri(scheme: 'http', host: proxyHost, port: proxyPort);
    if (Platform.isWindows) {
      final proxy = SystemProxyService.findProxy(uri);
      if (proxy.startsWith('PROXY ')) {
        return Uri.parse('http://${proxy.substring(6)}');
      }
    }
    return null;
  }

  HttpClient createHttpClient({int? maxConnectionsPerHost}) {
    final client = HttpClient()
      // 默认 15 秒就回收空闲连接。图片列表滚动、连续翻页时，连接刚建好
      // 就被丢掉，下一屏又要重做 TCP + TLS 握手。延长到 30 秒让连接真正
      // 复用起来。
      ..idleTimeout = const Duration(seconds: 30)
      // dart:io 默认不设连接超时：对端不响应时会一直挂着。显式给 10 秒。
      ..connectionTimeout = const Duration(seconds: 10);
    if (maxConnectionsPerHost != null) {
      client.maxConnectionsPerHost = maxConnectionsPerHost;
    }
    if (hasProxy) {
      client.findProxy = (_) => 'PROXY $proxyHost:$proxyPort';
    } else if (Platform.isWindows) {
      client.findProxy = SystemProxyService.findProxy;
    }
    if (allowBadCertificates) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    return client;
  }

  IOHttpClientAdapter createAdapter() =>
      IOHttpClientAdapter(createHttpClient: createHttpClient);

  NetworkConfig copyWith({
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    String? proxyHost,
    int? proxyPort,
    bool? clearProxy,
    bool? allowBadCertificates,
    bool? enableLog,
  }) {
    final shouldClearProxy = clearProxy ?? false;
    return NetworkConfig(
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      proxyHost: shouldClearProxy ? null : proxyHost ?? this.proxyHost,
      proxyPort: shouldClearProxy ? null : proxyPort ?? this.proxyPort,
      allowBadCertificates: allowBadCertificates ?? this.allowBadCertificates,
      enableLog: enableLog ?? this.enableLog,
    );
  }

  static NetworkConfig fromSettings({
    Duration connectTimeout = const Duration(seconds: 12),
    Duration receiveTimeout = const Duration(seconds: 12),
    Duration? sendTimeout,
  }) {
    final bool proxyEnable = GStorage.getSetting(SettingsKeys.proxyEnable);
    if (!proxyEnable) {
      return NetworkConfig(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        sendTimeout: sendTimeout,
      );
    }

    final proxyUrl = GStorage.getSetting(SettingsKeys.proxyUrl);
    final parsed = ProxyUtils.parseProxyUrl(proxyUrl);
    if (parsed == null) {
      KazumiLogger().w('Proxy: 代理地址格式错误或为空');
      return NetworkConfig(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        sendTimeout: sendTimeout,
      );
    }

    return NetworkConfig(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      proxyHost: parsed.$1,
      proxyPort: parsed.$2,
      // 只对本机回环代理放行自签证书：本地抓包/代理软件会做 MITM。
      // 远端代理不能关校验——那等于对所有站点放弃 HTTPS 保护，
      // 账号 token 与更新安装包都可能被中间人替换。
      allowBadCertificates: ProxyUtils.isLoopbackHost(parsed.$1),
    );
  }
}
