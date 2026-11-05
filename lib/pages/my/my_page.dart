import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/account/account_profile_page.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/pages/my/my_space_view.dart';
import 'package:kazumi/services/account/account_service.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key, required this.controller});

  final MyController controller;

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  bool _attached = false;

  /// 登录/登出/资料变更时刷新头部（AccountService 是 ChangeNotifier，
  /// Observer 感知不到它）。
  void _onAccountChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    AccountService().ensureLoaded();
    AccountService().addListener(_onAccountChanged);
  }

  @override
  void dispose() {
    AccountService().removeListener(_onAccountChanged);
    _setAttached(false);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setAttached(!RouteVisibility.isCoveredOf(context));
  }

  @override
  void didUpdateWidget(covariant MyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_attached && oldWidget.controller != widget.controller) {
      oldWidget.controller.detach();
      widget.controller.attach();
    }
  }

  void _setAttached(bool value) {
    if (_attached == value) return;
    _attached = value;
    if (value) {
      widget.controller.attach();
    } else {
      widget.controller.detach();
    }
  }

  void _open(MyDestination destination) =>
      context.pushNamed(switch (destination) {
        MyDestination.theme => '/settings/theme',
        MyDestination.player => '/settings/player',
        MyDestination.danmaku => '/settings/danmaku/',
        MyDestination.rules => '/settings/plugin/',
        MyDestination.history => '/settings/history/',
        MyDestination.downloads => '/settings/download/',
        MyDestination.sync => '/settings/account',
        MyDestination.storage => '/settings/storage',
        MyDestination.about => '/settings/about/',
      });

  @override
  Widget build(BuildContext context) {
    final account = AccountService()..ensureLoaded();
    return Scaffold(
      appBar: SysAppBar(
        toolbarHeight: 72,
        leading: MediaQuery.sizeOf(context).width < 600
            ? IconButton(
                tooltip: '打开导航菜单',
                onPressed: openAppDrawer,
                icon: const Icon(Icons.menu_rounded),
              )
            : null,
        title: Text(
          '个人主页',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        needTopOffset: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: MySettingsButton(
              onTap: () => context.pushNamed('/settings/'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Observer(
          builder: (context) {
            final stats = widget.controller.watchStats;
            final loggedIn = account.loggedIn;
            return MySpaceView(
              stats: stats,
              onOpen: _open,
              profile: ProfileHeaderData(
                avatarUrl: account.avatarUrl,
                nickname: loggedIn ? account.nickname : '',
                joinedAt: loggedIn && account.profile!.createdAt > 0
                    ? account.profile!.createdAt
                    : null,
                subtitle: loggedIn
                    ? '看过 ${stats.watchedBangumiCount} 部番剧 · ${stats.watchedEpisodeCount} 集'
                    : '登录凉次元账号，同步收藏与观看足迹',
                isOwn: true,
              ),
              onProfileTap: loggedIn
                  ? () => context.pushNamed(
                      '/settings/profile/${account.profile?.id ?? 0}',
                    )
                  : () => context.pushNamed('/settings/account'),
            );
          },
        ),
      ),
    );
  }
}
