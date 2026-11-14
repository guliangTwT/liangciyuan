import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/pages/popular/popular_page.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 渲染首页骨架，检查顶部固定区（标题栏 + 频道栏 + 搜索条）的排版。
///
/// 测试环境没有网络，数据请求会失败并进入错误态——正好用来确认
/// 「出错时顶部结构仍然完整、不塌陷」。
void main() {
  final outputDir = Directory('build/visual');
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('home_snapshot_');
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

  Future<void> capture(
    WidgetTester tester,
    String name,
    Widget child, {
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffbd4f9f)),
        ),
        home: RepaintBoundary(
          key: key,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              devicePixelRatio: 1.0,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      outputDir.createSync(recursive: true);
      File('${outputDir.path}/$name.png')
          .writeAsBytesSync(Uint8List.view(bytes.buffer));
    });
  }

  BangumiItem fakeItem(int id, String name) => BangumiItem(
        id: id,
        type: 2,
        name: name,
        nameCn: name,
        summary: '',
        airDate: '2024-04-01',
        airWeekday: 1,
        rank: id,
        // 非空地址才会走轮播分支；测试环境加载失败会显示占位图，
        // 但轮播的排版（渐变、标题、圆点）仍然会渲染出来。
        images: const {'large': 'https://example.invalid/cover.jpg'},
        tags: const [],
        alias: const [],
        ratingScore: 8.8,
        votes: 1200,
        votesCount: const [],
        info: '',
      );

  /// 预填数据：让页面走真实排版分支，而不是一上来就请求网络。
  PopularController filledController() {
    final controller = PopularController();
    controller.trendList.addAll([
      for (var i = 1; i <= 6; i++) fakeItem(i, '热门番剧 $i'),
    ]);
    controller.shelves.addAll([
      HomeShelf(
        title: '日漫',
        tag: '日本',
        items: [for (var i = 10; i < 16; i++) fakeItem(i, '日漫 $i')],
      ),
      HomeShelf(
        title: '国漫',
        tag: '国产',
        items: [for (var i = 20; i < 26; i++) fakeItem(i, '国漫 $i')],
      ),
    ]);
    controller.shelvesLoaded = true;
    return controller;
  }

  testWidgets('首页顶部结构（手机）', (tester) async {
    await capture(
      tester,
      'home-mobile',
      PopularPage(controller: filledController()),
    );
  });

  testWidgets('首页顶部结构（桌面）', (tester) async {
    await capture(
      tester,
      'home-desktop',
      PopularPage(controller: filledController()),
      size: const Size(1280, 860),
    );
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
