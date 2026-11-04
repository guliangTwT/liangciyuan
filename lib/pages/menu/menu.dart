import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/pages/router.dart';

class ScaffoldMenu extends StatefulWidget {
  const ScaffoldMenu({super.key, required this.location});

  final String location;

  @override
  State<ScaffoldMenu> createState() => _ScaffoldMenu();
}

class _ScaffoldMenu extends State<ScaffoldMenu> with RouteAware {
  final _outletKey = GlobalKey<RouterOutletState>();
  late int _selectedIndex = menu.indexForPath(widget.location);
  DateTime? _lastExitPromptAt;
  bool _isCovered = false;

  static const _labels = ['推荐', '时间表', '追番', '个人主页'];
  static const _icons = [
    Icons.auto_awesome_rounded,
    Icons.calendar_month_rounded,
    Icons.favorite_rounded,
    Icons.person_rounded,
  ];
  static const _unselectedIcons = [
    Icons.auto_awesome_outlined,
    Icons.calendar_month_outlined,
    Icons.favorite_border_rounded,
    Icons.person_outline_rounded,
  ];

  @override
  void didUpdateWidget(covariant ScaffoldMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _selectedIndex = menu.indexForPath(widget.location);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      rootRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() => _setCovered(true);

  @override
  void didPopNext() => _setCovered(false);

  void _setCovered(bool value) {
    if (!mounted || _isCovered == value) return;
    setState(() => _isCovered = value);
  }

  void _selectDestination(int index) {
    _lastExitPromptAt = null;
    if (index == _selectedIndex) return;
    final outlet = _outletKey.currentState;
    if (outlet == null) return;
    outlet.navigate('/tab${menu.getPath(index)}/');
    setState(() => _selectedIndex = index);
  }

  void _openRoute(String route) {
    if (MediaQuery.sizeOf(context).width < 600) {
      rootShellScaffoldKey.currentState?.closeDrawer();
    }
    context.pushNamed(route);
  }

  void _handleSystemBack(BuildContext context) {
    if (_outletKey.currentState?.maybePop() ?? false) {
      _lastExitPromptAt = null;
      return;
    }
    if (_selectedIndex != 0) {
      _selectDestination(0);
      return;
    }

    final now = DateTime.now();
    final lastPromptAt = _lastExitPromptAt;
    if (lastPromptAt == null ||
        now.difference(lastPromptAt) > const Duration(seconds: 2)) {
      _lastExitPromptAt = now;
      KazumiDialog.showToast(message: '再按一次退出应用', context: context);
      return;
    }

    _lastExitPromptAt = null;
    SystemNavigator.pop();
  }

  Widget _drawer(BuildContext context, {bool expanded = false}) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/images/logo/logo_rounded.png',
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '凉次元',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '星轨番剧库',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              height: 48,
              child: FilledButton.tonalIcon(
                onPressed: () => _openRoute('/search/'),
                icon: const Icon(Icons.search_rounded),
                label: Text(expanded ? '搜索番剧' : '搜索'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Text(
              '浏览',
              style: textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (var index = 0; index < _labels.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: ListTile(
                selected: _selectedIndex == index,
                leading: Icon(
                  _selectedIndex == index
                      ? _icons[index]
                      : _unselectedIcons[index],
                ),
                title: Text(_labels[index]),
                minLeadingWidth: 24,
                selectedTileColor: colors.secondaryContainer,
                selectedColor: colors.onSecondaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onTap: () {
                  if (MediaQuery.sizeOf(context).width < 600) {
                    rootShellScaffoldKey.currentState?.closeDrawer();
                  }
                  _selectDestination(index);
                },
              ),
            ),
          const Divider(height: 24, indent: 20, endIndent: 20),
          for (final entry in const [
            (Icons.history_rounded, '观看历史', '/settings/history/'),
            (Icons.download_rounded, '下载管理', '/settings/download/'),
            (Icons.tune_rounded, '设置', '/settings/'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: ListTile(
                leading: Icon(entry.$1),
                title: Text(entry.$2),
                minLeadingWidth: 24,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onTap: () => _openRoute(entry.$3),
              ),
            ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Text(
                '凉次元 · 由 Kazumi 开源项目改编',
                style: textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _outlet(BuildContext context) {
    return NotificationListener<NavigationNotification>(
      onNotification: (notification) => !notification.canHandlePop,
      child: RouterOutlet(key: _outletKey),
    );
  }

  Widget _mobileShell(BuildContext context) {
    return Scaffold(
      key: rootShellScaffoldKey,
      drawer: Drawer(width: 304, child: _drawer(context, expanded: true)),
      drawerEdgeDragWidth: 28,
      drawerEnableOpenDragGesture: true,
      body: _outlet(context),
      bottomNavigationBar: NavigationBar(
        destinations: [
          for (var index = 0; index < _labels.length; index++)
            NavigationDestination(
              selectedIcon: Icon(_icons[index]),
              icon: Icon(_unselectedIcons[index]),
              label: _labels[index],
            ),
        ],
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectDestination,
      ),
    );
  }

  Widget _desktopShell(BuildContext context, {required bool expanded}) {
    final colors = Theme.of(context).colorScheme;
    if (!expanded) {
      return Scaffold(
        backgroundColor: colors.surface,
        body: Row(
          children: [
            Material(
              color: colors.surfaceContainerLow,
              child: SafeArea(
                child: SizedBox(
                  width: 76,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'assets/images/logo/logo_rounded.png',
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      for (var index = 0; index < _labels.length; index++)
                        IconButton(
                          tooltip: _labels[index],
                          isSelected: _selectedIndex == index,
                          onPressed: () => _selectDestination(index),
                          icon: Icon(_unselectedIcons[index]),
                          selectedIcon: Icon(_icons[index]),
                        ),
                      const Divider(height: 24, indent: 18, endIndent: 18),
                      for (final entry in const [
                        (Icons.search_rounded, '搜索', '/search/'),
                        (Icons.history_rounded, '观看历史', '/settings/history/'),
                        (Icons.download_rounded, '下载管理', '/settings/download/'),
                        (Icons.tune_rounded, '设置', '/settings/'),
                      ])
                        IconButton(
                          tooltip: entry.$2,
                          onPressed: () => _openRoute(entry.$3),
                          icon: Icon(entry.$1),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: _outlet(context)),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: colors.surface,
      body: Row(
        children: [
          SizedBox(
            width: 260,
            child: Material(
              color: colors.surfaceContainerLow,
              child: _drawer(context, expanded: true),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _outlet(context)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RouteVisibility(
      isCovered: _isCovered,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleSystemBack(context);
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (width < 600) return _mobileShell(context);
            if (width < 1000) return _desktopShell(context, expanded: false);
            return _desktopShell(context, expanded: true);
          },
        ),
      ),
    );
  }
}
