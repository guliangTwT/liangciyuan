import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/plugin_editor/rule_help.dart';
import 'package:kazumi/pages/startup_loading_view.dart';

/// 视觉快照：把关键页面渲染成 PNG，输出到 build/visual/ 供人工核对。
///
/// 这不是断言型 golden（不同机器字体渲染有差异），只是把「渲染结果」留档，
/// 方便检查溢出条纹、被裁的文字、错位的按钮。
void main() {
  final outputDir = Directory('build/visual');

  BangumiItem item(int id, String name) => BangumiItem(
        id: id,
        type: 2,
        name: name,
        nameCn: name,
        summary: '',
        airDate: '2024-04-01',
        airWeekday: 1,
        rank: id,
        images: const {'large': '', 'common': ''},
        tags: const [],
        alias: const [],
        ratingScore: 8.8,
        votes: 100,
        votesCount: const [],
        info: '',
      );

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
    // toImage 需要真实的光栅化流程；在 fake-async 里会一直等下去，
    // 必须放到 runAsync 中执行。
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      outputDir.createSync(recursive: true);
      File('${outputDir.path}/$name.png').writeAsBytesSync(
        Uint8List.view(bytes.buffer),
      );
    });
  }

  testWidgets('渲染启动页', (tester) async {
    await capture(
      tester,
      'startup',
      const StartupLoadingView(status: '正在加载番剧来源…'),
    );
  });

  testWidgets('渲染卡片网格', (tester) async {
    await capture(
      tester,
      'cards',
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 8,
            childAspectRatio: 0.65 / 1.28,
            children: [
              for (var i = 1; i <= 9; i++)
                BangumiCardV(
                  bangumiItem: item(i, i == 1 ? '葬送的芙莉莲' : '番剧名称 $i'),
                  enableHero: false,
                ),
            ],
          ),
        ),
      ),
    );
  });

  testWidgets('渲染使用说明', (tester) async {
    await capture(
      tester,
      'rule-help',
      Scaffold(
        body: RuleHelpSheet(
          onOpenCatalog: () {},
          onOpenManager: () {},
          onOpenNetwork: () {},
        ),
      ),
    );
  });

  testWidgets('渲染无规则引导', (tester) async {
    await capture(
      tester,
      'no-source',
      Scaffold(
        body: NoSourceGuide(onOpenCatalog: () {}, onOpenHelp: () {}),
      ),
    );
  });

  testWidgets('渲染大字号说明', (tester) async {
    await capture(
      tester,
      'rule-help-large-text',
      Scaffold(
        body: RuleHelpSheet(onOpenCatalog: () {}, onOpenManager: () {}),
      ),
      textScale: 1.8,
    );
  });
}
