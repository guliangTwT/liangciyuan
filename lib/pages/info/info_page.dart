import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:window_manager/window_manager.dart';

import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/bean/card/bangumi_info_card.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/collect_button.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/info/info_actions_menu.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/info/info_tabview.dart';
import 'package:kazumi/pages/info/rating_dialog.dart';
import 'package:kazumi/pages/info/source_sheet.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/services/account/account_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/platform/desktop_window_config.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/device.dart';

class InfoPage extends StatefulWidget {
  const InfoPage({
    super.key,
    required this.inputBangumiItem,
    required this.infoController,
    required this.pluginsController,
  });

  final BangumiItem inputBangumiItem;
  final InfoController infoController;
  final PluginsController pluginsController;

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage>
    with SingleTickerProviderStateMixin {
  static const List<String> _infoTabs = <String>[
    '概览',
    '吐槽',
    '角色',
    '关联',
    '制作人员',
  ];
  static const Duration _minimumBangumiInfoLoadingDuration = Duration(
    milliseconds: 600,
  );

  InfoController get infoController => widget.infoController;
  late final TabController infoTabController;
  late final bool showRating;

  bool charactersIsLoading = false;
  bool charactersQueryTimeout = false;
  bool charactersIsEmpty = false;
  bool staffIsLoading = false;
  bool staffQueryTimeout = false;
  bool staffIsEmpty = false;
  bool _showBangumiInfoSkeleton = false;

  bool get _isShowingBangumiInfoSkeleton =>
      infoController.isLoading || _showBangumiInfoSkeleton;

  bool _needsBangumiInfoRefresh(BangumiItem bangumiItem) {
    // 只关心条目元数据（简介）是否缺失；评分已改为本站数据，
    // 不再依赖 Bangumi 的评分分布。
    return bangumiItem.summary == '';
  }

  Future<void> loadCharacters() async {
    if (charactersIsLoading) return;
    setState(() {
      charactersIsLoading = true;
      charactersQueryTimeout = false;
      charactersIsEmpty = false;
    });
    try {
      await infoController.queryBangumiCharactersByID(
        infoController.bangumiItem.id,
      );
      if (mounted) {
        setState(() {
          charactersIsLoading = false;
          if (infoController.characterList.isEmpty) {
            charactersIsEmpty = true;
          }
        });
      }
    } catch (e) {
      KazumiLogger().e('InfoPage: failed to load characters', error: e);
      if (mounted) {
        setState(() {
          charactersIsLoading = false;
          charactersQueryTimeout = true;
        });
      }
    }
  }

  Future<void> loadStaff() async {
    if (staffIsLoading) return;
    setState(() {
      staffIsLoading = true;
      staffQueryTimeout = false;
      staffIsEmpty = false;
    });
    try {
      await infoController.queryBangumiStaffsByID(
        infoController.bangumiItem.id,
      );
      if (mounted) {
        setState(() {
          staffIsLoading = false;
          if (infoController.staffList.isEmpty) {
            staffIsEmpty = true;
          }
        });
      }
    } catch (e) {
      KazumiLogger().e('InfoPage: failed to load staff', error: e);
      if (mounted) {
        setState(() {
          staffIsLoading = false;
          staffQueryTimeout = true;
        });
      }
    }
  }

  Future<void> loadRelations() async {
    try {
      await infoController.queryBangumiRelationsByID(
        infoController.bangumiItem.id,
      );
    } catch (e) {
      KazumiLogger().e('InfoPage: failed to load relations', error: e);
    }
  }

  @override
  void initState() {
    super.initState();
    infoController.bangumiItem = widget.inputBangumiItem;
    infoController.characterList.clear();
    infoController.staffList.clear();
    infoController.clearRelations();
    infoController.pluginSearchResponseList.clear();
    if (_needsBangumiInfoRefresh(infoController.bangumiItem)) {
      _showBangumiInfoSkeleton = true;
      _loadBangumiInfo();
    }
    infoTabController = TabController(length: _infoTabs.length, vsync: this);
    showRating = GStorage.getSetting(SettingsKeys.showRating);
    infoTabController.addListener(onInfoTabChanged);
    // 评分与条目信息并行拉取，不阻塞首屏。
    unawaited(infoController.loadRating(infoController.bangumiItem.id));
  }

  void onInfoTabChanged() {
    final index = infoTabController.index;
    if (index == 2 &&
        infoController.characterList.isEmpty &&
        !charactersIsLoading &&
        !charactersIsEmpty &&
        !charactersQueryTimeout) {
      loadCharacters();
    }
    if (index == 3 && infoController.canLoadRelations) {
      loadRelations();
    }
    if (index == 4 &&
        infoController.staffList.isEmpty &&
        !staffIsLoading &&
        !staffIsEmpty &&
        !staffQueryTimeout) {
      loadStaff();
    }
  }

  @override
  void dispose() {
    infoTabController.removeListener(onInfoTabChanged);
    infoController.characterList.clear();
    infoController.staffList.clear();
    infoController.clearRelations();
    infoController.pluginSearchResponseList.clear();
    infoTabController.dispose();
    super.dispose();
  }

  Future<void> _loadBangumiInfo() async {
    final loadingStartedAt = DateTime.now();
    try {
      // Attach metadata without replacing rendered image URLs.
      await infoController.queryBangumiInfoByID(
        infoController.bangumiItem.id,
        type: 'attach',
      );
    } catch (e) {
      KazumiLogger().e(
        'InfoPage: failed to query bangumi info by ID',
        error: e,
      );
    } finally {
      if (mounted) {
        await _waitForMinimumBangumiInfoLoadingDuration(loadingStartedAt);
      }
      if (mounted) {
        setState(() {
          _showBangumiInfoSkeleton = false;
        });
      }
    }
  }

  /// 打开评分面板。未登录时先引导登录。
  Future<void> _rate() async {
    final account = AccountService()..ensureLoaded();
    if (!account.loggedIn) {
      KazumiDialog.showToast(message: '打分需要先登录凉次元账号');
      context.pushNamed('/settings/account');
      return;
    }
    final current = infoController.rating?.myScore ?? 0;
    final selected = await showDialog<int>(
      builder: (context) => RatingDialog(
        title: infoController.bangumiItem.nameCn.isNotEmpty
            ? infoController.bangumiItem.nameCn
            : infoController.bangumiItem.name,
        initialScore: current,
      ),
      context: context,
    );
    if (!mounted || selected == null) return;
    try {
      final ok = await infoController.submitRating(
        infoController.bangumiItem.id,
        selected,
      );
      if (!mounted) return;
      KazumiDialog.showToast(message: ok ? '已提交评分' : '请先登录凉次元账号');
    } catch (e) {
      if (!mounted) return;
      KazumiDialog.showToast(
        message: e is AccountException ? e.message : '评分失败，请稍后重试',
      );
    }
  }

  void _startWatching() {
    if (widget.pluginsController.pluginList.isEmpty) {
      KazumiDialog.showToast(
        message: '还没有规则，无法开始观看',
        showActionButton: true,
        actionLabel: '添加规则',
        onActionPressed: () {
          if (mounted) context.pushNamed('/settings/plugin/');
        },
        duration: const Duration(seconds: 4),
      );
      return;
    }
    showAdaptiveBottomSheet<void>(
      context: context,
      maxHeightFactor: 0.88,
      builder: (_) => SourceSheet(infoController: infoController),
    );
  }

  Future<void> _waitForMinimumBangumiInfoLoadingDuration(
    DateTime loadingStartedAt,
  ) async {
    final elapsed = DateTime.now().difference(loadingStartedAt);
    final remaining = _minimumBangumiInfoLoadingDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showWindowButton = DesktopWindowConfig.showWindowButton;
    final topOffset = Platform.isMacOS && showWindowButton ? 22.0 : 0.0;
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar.medium(
                title: EmbeddedNativeControlArea(
                  child: dtb.DragToMoveArea(
                    child: Container(
                      width: double.infinity,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        infoController.bangumiItem.nameCn == ''
                            ? infoController.bangumiItem.name
                            : infoController.bangumiItem.nameCn,
                      ),
                    ),
                  ),
                ),
                automaticallyImplyLeading: false,
                scrolledUnderElevation: 0.0,
                leading: EmbeddedNativeControlArea(
                  child: IconButton(
                    onPressed: () {
                      context.maybePop();
                    },
                    icon: Icon(Icons.arrow_back),
                  ),
                ),
                actions: [
                  if (innerBoxIsScrolled)
                    EmbeddedNativeControlArea(
                      child: CollectButton(
                        bangumiItem: infoController.bangumiItem,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  EmbeddedNativeControlArea(
                    child: InfoActionsMenu(
                      bangumiItem: infoController.bangumiItem,
                    ),
                  ),
                  if (isDesktop() && !showWindowButton)
                    CloseButton(onPressed: () => windowManager.close()),
                  SizedBox(width: 8),
                ],
                toolbarHeight: kToolbarHeight + topOffset,
                stretch: true,
                centerTitle: false,
                expandedHeight:
                    308 + kTextTabBarHeight + kToolbarHeight + topOffset,
                collapsedHeight:
                    kTextTabBarHeight +
                    kToolbarHeight +
                    MediaQuery.paddingOf(context).top +
                    topOffset,
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  background: Observer(
                    builder: (context) {
                      final showBangumiInfoSkeleton =
                          _isShowingBangumiInfoSkeleton;
                      return Stack(
                        children: [
                          if (!showBangumiInfoSkeleton)
                            Positioned.fill(
                              bottom: kTextTabBarHeight,
                              child: IgnorePointer(
                                child: _InfoHeaderBackground(
                                  imageUrl:
                                      infoController
                                          .bangumiItem
                                          .images['large'] ??
                                      '',
                                ),
                              ),
                            ),
                          SafeArea(
                            bottom: false,
                            child: EmbeddedNativeControlArea(
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    kToolbarHeight,
                                    16,
                                    0,
                                  ),
                                  child: BangumiInfoCardV(
                                    bangumiItem: infoController.bangumiItem,
                                    isLoading: showBangumiInfoSkeleton,
                                    showRating: showRating,
                                    rating: infoController.rating,
                                    onRate: _rate,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                forceElevated: innerBoxIsScrolled,
                bottom: TabBar(
                  controller: infoTabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  dividerHeight: 0,
                  tabs: _infoTabs.map((name) => Tab(text: name)).toList(),
                ),
              ),
            ),
          ];
        },
        body: Observer(
          builder: (context) {
            final showBangumiInfoSkeleton = _isShowingBangumiInfoSkeleton;
            return InfoTabView(
              tabController: infoTabController,
              bangumiItem: infoController.bangumiItem,
              charactersQueryTimeout: charactersQueryTimeout,
              charactersIsEmpty: charactersIsEmpty,
              staffQueryTimeout: staffQueryTimeout,
              staffIsEmpty: staffIsEmpty,
              loadCharacters: loadCharacters,
              loadStaff: loadStaff,
              characterList: infoController.characterList,
              staffList: infoController.staffList,
              relationList: infoController.relationList,
              relationsIsLoading: infoController.relationsIsLoading,
              relationsQueryTimeout: infoController.relationsQueryTimeout,
              relationsHasLoaded: infoController.relationsHasLoaded,
              loadRelations: loadRelations,
              isLoading: showBangumiInfoSkeleton,
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: '开始观看',
        onPressed: _startWatching,
        label: const Text('开始观看'),
        icon: const Icon(Icons.play_arrow_rounded),
      ),
    );
  }
}

class _InfoHeaderBackground extends StatelessWidget {
  const _InfoHeaderBackground({required this.imageUrl});

  static const double _downsample = 0.5;
  static const double _blurSigma = 15.0;
  static const double _opacity = 0.4;
  static const double _edgeBleed = 32.0;
  static const double _bottomFeatherHeight = 48.0;

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }

        final rasterWidth = width * _downsample;
        final rasterHeight = (height + _edgeBleed) * _downsample;

        final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ShaderMask(
                shaderCallback: (bounds) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.transparent],
                    stops: [0.8, 1],
                  ).createShader(bounds);
                },
                child: Align(
                  alignment: Alignment.topCenter,
                  child: RepaintBoundary(
                    child: Transform.scale(
                      scale: 1 / _downsample,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.low,
                      child: SizedBox(
                        width: rasterWidth,
                        height: rasterHeight,
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: _blurSigma * _downsample,
                            sigmaY: _blurSigma * _downsample,
                          ),
                          child: NetworkImgLayer(
                            src: imageUrl,
                            width: rasterWidth,
                            height: rasterHeight,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            filterQuality: FilterQuality.low,
                            color: Colors.white.withValues(alpha: _opacity),
                            colorBlendMode: BlendMode.modulate,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _bottomFeatherHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        backgroundColor.withValues(alpha: 0),
                        backgroundColor.withValues(alpha: 0.55),
                        backgroundColor,
                      ],
                      stops: const [0, 0.72, 1],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

