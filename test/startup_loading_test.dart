import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/startup_loading_view.dart';

/// 启动页的回归测试。
///
/// 之前初始化页是 `Scaffold(body: Container())`——纯空白，冷启动慢时
/// 用户会以为应用没响应。这里锁住「至少能看到品牌与状态文案」这一点。
void main() {
  Widget wrap({String? status}) => MaterialApp(
        home: StartupLoadingView(status: status),
      );

  testWidgets('显示品牌名与副标题', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('凉次元'), findsOneWidget);
    expect(find.text('星轨番剧库'), findsOneWidget);
  });

  testWidgets('有状态文案时显示，没有时不占额外文字', (tester) async {
    await tester.pumpWidget(wrap(status: '正在加载番剧来源…'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('正在加载番剧来源…'), findsOneWidget);

    await tester.pumpWidget(wrap());
    // 文案是 AnimatedSwitcher 淡出的，等动画走完再断言。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('正在加载番剧来源…'), findsNothing);
  });

  testWidgets('系统关闭动画时不崩溃', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const StartupLoadingView(status: '正在读取本地数据…'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('正在读取本地数据…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('大字号下不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: const StartupLoadingView(status: '正在准备下载服务…'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });
}
