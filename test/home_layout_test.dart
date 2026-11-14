import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/plugin_editor/rule_help.dart';

/// 首页与说明面板的排版回归。
///
/// 这些页面依赖大量固定尺寸（卡片宽高比、频道栏高度、横滑卡片宽度），
/// 一旦某处算错，表现就是溢出条纹或文字被裁——在真机上很难定位，
/// 所以在测试里用几种典型尺寸各跑一遍。
void main() {
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

  group('BangumiCardV', () {
    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 220,
                child: BangumiCardV(
                  bangumiItem: item(1, '葬送的芙莉莲'),
                  enableHero: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('手机尺寸无溢出', (tester) async {
      await pumpAt(tester, const Size(390, 844));
      expect(tester.takeException(), isNull);
      expect(find.text('葬送的芙莉莲'), findsOneWidget);
    });

    testWidgets('桌面尺寸无溢出', (tester) async {
      await pumpAt(tester, const Size(1440, 900));
      expect(tester.takeException(), isNull);
    });

    testWidgets('超大字号下标题被截断而不是溢出', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 120,
                  height: 220,
                  child: BangumiCardV(
                    bangumiItem: item(2, '这是一个非常非常长的番剧名字用来测试截断'),
                    enableHero: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });
  });

  group('RuleHelpSheet', () {
    Future<void> pumpSheet(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RuleHelpSheet(
              onOpenCatalog: () {},
              onOpenManager: () {},
              onOpenNetwork: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('手机竖屏：说明内容完整可滚动', (tester) async {
      await pumpSheet(tester, const Size(390, 844));
      expect(tester.takeException(), isNull);
      expect(find.text('番剧来源使用说明'), findsOneWidget);
      expect(find.textContaining('规则 = 一个番剧网站'), findsOneWidget);
    });

    testWidgets('小屏：标题与按钮不溢出', (tester) async {
      await pumpSheet(tester, const Size(320, 480));
      expect(tester.takeException(), isNull);
    });

    testWidgets('大字号下不溢出', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: RuleHelpSheet(
                onOpenCatalog: () {},
                onOpenManager: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });
  });

  group('NoSourceGuide', () {
    testWidgets('没有规则时给出两个入口', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoSourceGuide(onOpenCatalog: () {}, onOpenHelp: () {}),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('还没有可用的番剧来源'), findsOneWidget);
      expect(find.text('去规则仓库挑选'), findsOneWidget);
      expect(find.text('先看看使用说明'), findsOneWidget);
    });
  });
}
