import 'package:flutter/material.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final rootShellScaffoldKey = GlobalKey<ScaffoldState>();

void openAppDrawer() => rootShellScaffoldKey.currentState?.openDrawer();

/// 请求切换底部标签（0=推荐 1=时间表 2=追番 3=个人主页）。
///
/// 由标签外壳注册：直接操作 RouterOutlet 不会同步底部导航栏的选中态，
/// 所以页面内部（例如首页的「日历」按钮）必须走这个入口。
void Function(int index)? _tabSwitchHandler;

void registerTabSwitchHandler(void Function(int index)? handler) {
  _tabSwitchHandler = handler;
}

void requestTab(int index) => _tabSwitchHandler?.call(index);

/// Lets [RouteAware] pages learn they were covered or revealed again.
///
/// Restricted to [PageRoute] on purpose: dialogs and bottom sheets are
/// PopupRoutes, and sitting under one does not make a page hidden.
final rootRouteObserver = RouteObserver<PageRoute<void>>();

final _closedByExternalNavigation = <Route<Object?>>{};

/// Marks [route] to close, not be covered, when a deep link opens a page.
void closeOnExternalNavigation(Route<Object?> route) {
  _closedByExternalNavigation.add(route);
}

void clearExternalNavigationMark(Route<Object?> route) {
  _closedByExternalNavigation.remove(route);
}

/// Pops marked routes and everything above them like the back button, so
/// [PopScope] and local history entries unwind. False if a route vetoes.
bool popForExternalNavigation(NavigatorState navigator) {
  bool hasMarkedRoute() => _closedByExternalNavigation.any(
    (route) => route.isActive && route.navigator == navigator,
  );

  var vetoed = false;
  navigator.popUntil((current) {
    if (!hasMarkedRoute()) return true;
    vetoed = current.popDisposition == RoutePopDisposition.doNotPop;
    return vetoed;
  });
  return !vetoed;
}
