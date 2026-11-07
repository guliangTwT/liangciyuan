import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_layout.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/collect/collect_library_view.dart';
import 'package:kazumi/pages/collect/collect_sync_dialog.dart';
import 'package:kazumi/services/account/account_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/account_sync_service.dart';

class CollectPage extends StatefulWidget {
  const CollectPage({super.key, required this.controller});

  final CollectController controller;

  @override
  State<CollectPage> createState() => _CollectPageState();
}

class _CollectPageState extends State<CollectPage> with KazumiDialogOwner {
  CollectController get collectController => widget.controller;
  bool get _syncDialogOpen => dialogs.isRunning;
  final Set<int> _pendingIds = {};
  late CollectLayout _layout;

  /// 当前设置下要同步的步骤。顺序与账号页一致：屏蔽词 → 观看记录 → 收藏。
  List<CollectSyncStep> get _enabledSteps => [
    if (GStorage.getSetting(SettingsKeys.webDavEnableDanmakuShield))
      CollectSyncStep.shield,
    if (GStorage.getSetting(SettingsKeys.webDavEnableHistory))
      CollectSyncStep.history,
    if (GStorage.getSetting(SettingsKeys.webDavEnableCollect))
      CollectSyncStep.collect,
  ];

  String? get _blockedReason {
    final account = AccountService()..ensureLoaded();
    if (!account.loggedIn) return '请先登录凉次元账号';
    if (!GStorage.getSetting(SettingsKeys.accountSyncEnable)) {
      return '请先开启账号云同步';
    }
    return '请在账号设置里开启要同步的内容';
  }

  @override
  void initState() {
    super.initState();
    // Read once; page switches never change the saved default.
    _layout = CollectLayout.fromValue(
      GStorage.getSetting(SettingsKeys.defaultCollectLayout),
    );
    collectController.loadCollectibles();
  }

  void _changeLayout(CollectLayout layout) {
    if (_layout == layout) return;
    setState(() => _layout = layout);
  }

  Future<void> _changeType(BangumiItem item, CollectType type) async {
    if (_syncDialogOpen || _pendingIds.contains(item.id)) return;
    setState(() => _pendingIds.add(item.id));
    try {
      await collectController.addCollect(item, type: type.value);
    } catch (_) {
      KazumiDialog.showToast(message: '修改收藏状态失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _pendingIds.remove(item.id));
    }
  }

  Future<void> _sync() async {
    if (_syncDialogOpen || _pendingIds.isNotEmpty) return;
    final steps = _enabledSteps;
    final canSync = AccountSyncService.canSync && steps.isNotEmpty;
    await dialogs.run((task) async {
      final destination = await task.show<CollectSyncDestination>(
        builder: (_) => CollectSyncDialog(
          steps: steps,
          canSync: canSync,
          blockedReason: _blockedReason,
          onSync: canSync
              ? () => AccountSyncService().syncAll(
                    reloadCollectibles: collectController.loadCollectibles,
                  )
              : null,
          reloadCollectibles: collectController.loadCollectibles,
        ),
      );
      task.withContext(
        (context) => context.pushNamed(switch (destination) {
          CollectSyncDestination.accountSettings => '/settings/account/',
        }),
      );
    }, errorMessage: '同步未完成，请稍后重试');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        needTopOffset: false,
        toolbarHeight: 72,
        leading: MediaQuery.sizeOf(context).width < 600
            ? IconButton(
                tooltip: '打开导航菜单',
                onPressed: openAppDrawer,
                icon: const Icon(Icons.menu_rounded),
              )
            : null,
        title: Text(
          '追番',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: '同步收藏、观看记录与弹幕屏蔽词',
              child: StateActionButton.tonal(
                text: '同步',
                onPressed: _syncDialogOpen || _pendingIds.isNotEmpty
                    ? null
                    : _sync,
                icon: Icons.sync_rounded,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Observer(
          builder: (context) => CollectLibraryView(
            entries: collectController.collectibles.toList(),
            showRating: GStorage.getSetting(SettingsKeys.showRating),
            layout: _layout,
            onLayoutChanged: _changeLayout,
            canEdit: (item) =>
                !_syncDialogOpen && !_pendingIds.contains(item.id),
            onOpen: (item) => context.pushNamed('/info/', arguments: item),
            onChangeType: (item, type) => unawaited(_changeType(item, type)),
          ),
        ),
      ),
    );
  }
}
