import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/network/image_file_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 图片连接复用的回归测试。
///
/// 曾经的实现是**每个图片请求**新建一个 `IOClient`，响应体读完就 `close()`。
/// 首页一屏几十张封面 = 几十次 TCP + TLS 握手，而且一个连接都用不上第二次；
/// 滚动时新图片只能排在握手后面，观感就是「图一张张挤出来」。
///
/// 这里起一个真实的本机 HTTP 服务，统计**实际建立的 TCP 连接数**：
/// 复用生效时，连续请求同一 host 的多个资源应该只开少量连接。
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('image_service_test_');
    PathProviderPlatform.instance = _TestPaths(tempDir.path);
    Hive.init(tempDir.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('连续图片请求复用连接，而不是每张图重新握手', () async {
    var acceptedConnections = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // 每建立一条新 TCP 连接回调一次。dart:io 的 HttpServer 没有直接的
    // 「连接数」计数，用 connectionInfo 在响应里回传更可靠；这里改用
    // 请求逐步观察 remotePort —— 同一连接上多个请求的 remotePort 相同。
    final portsSeen = <int>{};
    addTearDown(() => server.close(force: true));

    server.listen((request) async {
      acceptedConnections++;
      final port = request.connectionInfo?.remotePort;
      if (port != null) portsSeen.add(port);
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType('image', 'jpeg');
      request.response.add(List<int>.filled(1024, 7));
      await request.response.close();
    });

    final service = ImageFileService();
    addTearDown(service.close);

    // 串行请求 6 张图：第一条必须新建连接，其余应当复用。
    for (var i = 0; i < 6; i++) {
      final response = await service.get(
        'http://127.0.0.1:${server.port}/cover-$i.jpg',
      );
      // 必须把响应体读完，连接才会归还到池里。
      await response.content.drain<void>();
    }

    expect(acceptedConnections, 6, reason: '六次请求都应到达服务端');
    expect(
      portsSeen.length,
      1,
      reason: '六次请求应复用同一条连接；大于 1 说明每次都在重新握手',
    );
  });

  test('close 之后拒绝服务，不再新建连接', () async {
    final service = ImageFileService();
    service.close();
    expect(
      () => service.get('http://127.0.0.1:1/x.jpg'),
      throwsA(isA<StateError>()),
    );
  });

  test('reset 可以丢弃连接池而仍然可用', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = 200;
      request.response.add(List<int>.filled(64, 1));
      await request.response.close();
    });

    final service = ImageFileService();
    addTearDown(service.close);
    final url = 'http://127.0.0.1:${server.port}/a.jpg';

    await (await service.get(url)).content.drain<void>();
    // 换代理后必须能丢掉旧连接；清掉之后仍应能正常取图。
    service.reset();
    final afterReset = await service.get(url);
    expect(afterReset.statusCode, 200);
    await afterReset.content.drain<void>();
  });
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}
