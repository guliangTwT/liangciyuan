import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/platform/desktop_window_config.dart';
import 'package:kazumi/utils/device.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:window_manager/window_manager.dart';

/// 首页：频道栏 + 搜索条 + 焦点轮播 + 横滑分区。
///
/// 结构上分两条路径：
/// - 「推荐」频道：轮播 + 「推荐 · 日漫 / 国漫 / 剧场」横向货架；
/// - 其它频道：单个标签的无限网格（保留原来的瀑布式浏览）。
class PopularPage extends StatefulWidget {
  const PopularPage({super.key, required this.controller});

  final PopularController controller;

  @override
  State<PopularPage> createState() => _PopularPageState();
}

class _PopularPageState extends State<PopularPage> {
  late final ScrollController scrollController;
  PopularController get popularController => widget.controller;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      initialScrollOffset: popularController.scrollOffset,
    );
    scrollController.addListener(scrollListener);
    if (popularController.trendList.isEmpty) {
      popularController.queryBangumiByTrend();
    }
    if (!popularController.shelvesLoaded) {
      popularController.loadHomeShelves();
    }
  }

  @override
  void dispose() {
    scrollController.removeListener(scrollListener);
    scrollController.dispose();
    super.dispose();
  }

  void scrollListener() {
    popularController.scrollOffset = scrollController.offset;
    // 货架模式下不做无限加载：首页是「每个分区看一屏」的浏览入口，
    // 想继续翻应切到对应频道。
    if (popularController.currentChannel != HomeChannel.recommend) {
      _maybeLoadMore();
    }
  }

  void _maybeLoadMore() {
    if (!scrollController.hasClients) return;
    if (scrollController.position.pixels <
        scrollController.position.maxScrollExtent - 200) {
      return;
    }
    if (popularController.isLoadingMore) return;
    KazumiLogger().i('PopularPage: fetching next batch');
    popularController.queryBangumiByTag();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 用实际可用宽度计算网格列数：桌面端窗口被侧边栏吃掉 76/260，
      // 只看 MediaQuery 会把卡片排得太密。
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth;
          return Observer(
            builder: (context) {
              final channel = popularController.currentChannel;
              final isRecommend = channel == HomeChannel.recommend;
              return CustomScrollView(
                controller: scrollController,
                slivers: [
                  _buildAppBar(context, isRecommend: isRecommend),
                  if (isRecommend)
                    ..._buildRecommendSlivers(context, contentWidth)
                  else
                    ..._buildChannelSlivers(context, contentWidth),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 顶部：标题 + 频道栏 + 搜索
  // ---------------------------------------------------------------------------

  Widget _buildAppBar(BuildContext context, {required bool isRecommend}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    // 手机走抽屉导航；平板/桌面已有侧边栏，不需要汉堡键。
    final menuButton = compact
        ? IconButton(
            tooltip: '打开导航菜单',
            onPressed: openAppDrawer,
            icon: const Icon(Icons.menu_rounded),
          )
        : null;
    return SliverAppBar(
      pinned: true,
      floating: false,
      stretch: false,
      elevation: 0,
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 56,
      titleSpacing: 0,
      centerTitle: false,
      leadingWidth: menuButton == null ? 0 : 56,
      leading: menuButton,
      title: Padding(
        padding: EdgeInsets.only(left: menuButton == null ? 20 : 4),
        child: Row(
          children: [
            Text(
              '凉次元',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            if (!isRecommend) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  popularController.currentChannel.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: '搜索',
          onPressed: () => context.pushNamed('/search/'),
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(
          tooltip: '观看历史',
          onPressed: () => context.pushNamed('/settings/history/'),
          icon: const Icon(Icons.history_rounded),
        ),
        if (isDesktop() && !DesktopWindowConfig.showWindowButton)
          IconButton(
            tooltip: '退出',
            onPressed: () => windowManager.close(),
            icon: const Icon(Icons.close_rounded),
          ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(_chromeHeight(context) + 1),
        child: _buildChrome(context),
      ),
    );
  }

  /// 顶部固定区高度：频道栏 46 + 搜索条 62 + 分割线 1，跟着字号缩放。
  ///
  /// 三个数与 [_buildChrome] 里的实际高度必须一致，否则 AppBar 会把
  /// 底部内容裁掉一截（表现为频道文字被切掉半行）。
  double _chromeHeight(BuildContext context) {
    final extra = MediaQuery.textScalerOf(context).scale(16) - 16;
    return 46 + 62 + 1 + extra.clamp(0.0, 18.0);
  }

  Widget _buildChrome(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChannelBar(
          current: popularController.currentChannel,
          onSelect: _selectChannel,
        ),
        _HomeSearchBar(
          onSearch: () => context.pushNamed('/search/'),
          // 日历按钮：和截图一致，直接跳时间表。
          onCalendar: () => requestTab(1),
        ),
        const Divider(height: 1, thickness: 1),
      ],
    );
  }

  Future<void> _selectChannel(HomeChannel channel) async {
    if (channel == popularController.currentChannel) return;
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
    popularController.setChannel(channel);
    if (channel == HomeChannel.recommend) {
      if (popularController.trendList.isEmpty) {
        await popularController.queryBangumiByTrend(type: 'init');
      }
      if (!popularController.shelvesLoaded) {
        await popularController.loadHomeShelves();
      }
    } else {
      await popularController.queryBangumiByTag(type: 'init');
    }
  }

  // ---------------------------------------------------------------------------
  // 推荐频道
  // ---------------------------------------------------------------------------

  List<Widget> _buildRecommendSlivers(
    BuildContext context, double contentWidth) {
    if (popularController.isTimeOut && popularController.trendList.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 420,
            child: BangumiMirrorErrorWidget(
              onRetry: () {
                popularController.queryBangumiByTrend(type: 'init');
                popularController.loadHomeShelves(force: true);
              },
              onSettingsReturned: () {
                if (mounted) setState(() {});
              },
            ),
          ),
        ),
      ];
    }

    final trend = popularController.trendList.toList();
    final shelves = popularController.shelves.toList();
    final slivers = <Widget>[];

    // 轮播：取趋势前 5 个有封面的，横向大图。
    final featured = trend
        .where((item) => (item.images['large'] ?? '').isNotEmpty)
        .take(5)
        .toList();

    if (trend.isEmpty && shelves.isEmpty) {
      slivers.add(
        const SliverToBoxAdapter(
          child: SizedBox(
            height: 320,
            child: Center(child: LoadingIndicator()),
          ),
        ),
      );
      return slivers;
    }

    if (featured.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _FeaturedBanner(items: featured, contentWidth: contentWidth),
        ),
      );
    }

    final edge = _contentPadding(contentWidth);

    if (shelves.isEmpty) {
      // 分区还没回来（或全部失败）时，先用趋势列表铺一个网格，别留白。
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(edge, 4, edge, 0),
          sliver: _BangumiGrid(items: trend, contentWidth: contentWidth),
        ),
      );
      return slivers;
    }

    for (final shelf in shelves) {
      slivers.add(
        SliverToBoxAdapter(
          child: _ShelfRow(
            key: ValueKey('shelf-${shelf.tag}'),
            title: '推荐 · ${shelf.title}',
            items: shelf.items,
            contentWidth: contentWidth,
            onMore: () {
              final channel = HomeChannel.values.firstWhere(
                (c) => c.tag == shelf.tag,
                orElse: () => HomeChannel.recommend,
              );
              _selectChannel(channel);
            },
          ),
        ),
      );
    }

    // 分区之后收一个「大家都在看」网格：首屏之外的补充内容，
    // 也保证分区全部拉取失败时页面仍然有东西可点。
    if (trend.isNotEmpty) {
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(edge + 4, 16, edge, 0),
          sliver: SliverToBoxAdapter(
            child: _SectionTitle(title: '大家都在看', onMore: null),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(edge, 0, edge, 0),
          sliver: _BangumiGrid(items: trend, contentWidth: contentWidth),
        ),
      );
    }
    return slivers;
  }

  // ---------------------------------------------------------------------------
  // 普通频道
  // ---------------------------------------------------------------------------

  List<Widget> _buildChannelSlivers(
    BuildContext context,
    double contentWidth,
  ) {
    final items = popularController.bangumiList.toList();
    if (popularController.isTimeOut && items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 420,
            child: BangumiMirrorErrorWidget(
              onRetry: () => popularController.queryBangumiByTag(type: 'init'),
              onSettingsReturned: () {
                if (mounted) setState(() {});
              },
            ),
          ),
        ),
      ];
    }
    final edge = _contentPadding(contentWidth);
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(edge, 12, edge, 0),
        sliver: _BangumiGrid(items: items, contentWidth: contentWidth),
      ),
      SliverToBoxAdapter(
        child: Observer(
          builder: (_) => AnimatedOpacity(
            opacity: popularController.isLoadingMore ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: popularController.isLoadingMore
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: LoadingIndicator(size: 28)),
                  )
                : const SizedBox(height: 8),
          ),
        ),
      ),
    ];
  }
}

// -----------------------------------------------------------------------------
// 搜索条
// -----------------------------------------------------------------------------

/// 与截图一致的搜索条：左侧放大镜 + 占位文案，右侧圆形日历按钮。
///
/// 这里不做内联输入：搜索页本身有历史记录、筛选、图搜等功能，
/// 点一下跳过去比在首页塞一个半成品输入框更清楚。
class _HomeSearchBar extends StatelessWidget {
  const _HomeSearchBar({required this.onSearch, required this.onCalendar});

  final VoidCallback onSearch;
  final VoidCallback onCalendar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: '搜索视频',
              child: Material(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onSearch,
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Icon(
                          Icons.search_rounded,
                          size: 21,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '点击搜索视频',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: '打开时间表',
            child: Material(
              color: colors.primary,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onCalendar,
                child: Tooltip(
                  message: '时间表',
                  child: SizedBox.square(
                    dimension: 48,
                    child: Icon(
                      Icons.calendar_month_rounded,
                      size: 22,
                      color: colors.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 频道栏
// -----------------------------------------------------------------------------

class _ChannelBar extends StatelessWidget {
  const _ChannelBar({required this.current, required this.onSelect});

  final HomeChannel current;
  final ValueChanged<HomeChannel> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    return SizedBox(
      // 固定 46 + 跟随字号的一点余量：大字号时文字不会被上下裁掉。
      height: 46 + (scaler.scale(16) - 16).clamp(0.0, 18.0),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: HomeChannel.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final channel = HomeChannel.values[index];
          final selected = channel == current;
          return Center(
            child: TextButton(
              onPressed: () => onSelect(channel),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                foregroundColor:
                    selected ? colors.onSurface : colors.onSurfaceVariant,
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(channel.label),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    height: 3,
                    width: selected ? 18 : 0,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 焦点轮播
// -----------------------------------------------------------------------------

class _FeaturedBanner extends StatefulWidget {
  const _FeaturedBanner({required this.items, required this.contentWidth});

  final List<BangumiItem> items;
  final double contentWidth;

  @override
  State<_FeaturedBanner> createState() => _FeaturedBannerState();
}

class _FeaturedBannerState extends State<_FeaturedBanner> {
  final _pageController = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final edge = _contentPadding(widget.contentWidth);
    return Padding(
      padding: EdgeInsets.fromLTRB(edge, 12, edge, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 手机竖屏用 2:1；宽屏用更扁的比例，并给高度封顶——
          // 否则 1280 宽时横幅会高到 450px，把首屏内容全挤下去。
          final width = constraints.maxWidth;
          final height = width < 600
              ? width / 2.0
              : (width / 2.8).clamp(200.0, 300.0);
          return Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PageView.builder(
                        controller: _pageController,
                        itemCount: widget.items.length,
                        onPageChanged: (value) => setState(() => _index = value),
                        itemBuilder: (context, index) => _BannerCard(
                          item: widget.items[index],
                          enableHero: index == _index,
                        ),
                      ),
                      // 底部渐变，保证白色文字永远可读。
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.05),
                                Colors.black.withValues(alpha: 0.62),
                              ],
                              stops: const [0.45, 0.7, 1],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        // 给右下角的圆点留出位置，标题不会被压到点下面。
                        right: 96,
                        bottom: 14,
                        child: _BannerCaption(
                          item: widget.items[_index.clamp(0, widget.items.length - 1)],
                        ),
                      ),
                      Positioned(
                        right: 14,
                        bottom: 16,
                        child: _Dots(
                          count: widget.items.length,
                          index: _index,
                          activeColor: Colors.white,
                          inactiveColor: Colors.white.withValues(alpha: 0.45),
                          onTap: (i) => _pageController.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 页码用右下角的圆点表示，不再额外占一行文字。
            ],
          );
        },
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.item, required this.enableHero});

  final BangumiItem item;
  final bool enableHero;

  @override
  Widget build(BuildContext context) {
    final image = _BannerImage(item: item, enableHero: enableHero);
    return GestureDetector(
      onTap: () => context.pushNamed('/info/', arguments: item),
      child: image,
    );
  }
}

class _BannerImage extends StatelessWidget {
  const _BannerImage({required this.item, required this.enableHero});

  final BangumiItem item;
  final bool enableHero;

  @override
  Widget build(BuildContext context) {
    final src = item.images['large'] ?? item.images['common'] ?? '';
    // 必须给出有限的宽高：NetworkImgLayer 会按尺寸计算解码缓存，
    // 传 infinity 会在 cacheSize() 里抛 "Infinity or NaN toInt"。
    final image = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 1.0;
        final height = constraints.hasBoundedHeight && constraints.maxHeight > 0
            ? constraints.maxHeight
            : 1.0;
        // 和列表卡片共用同一层磁盘缓存，来回切频道不会重新下载大图。
        return NetworkImgLayer(
          src: src,
          width: width,
          height: height,
          fit: BoxFit.cover,
          borderRadius: BorderRadius.zero,
        );
      },
    );
    if (!enableHero) return image;
    return Hero(
      tag: item.id,
      transitionOnUserGestures: true,
      flightShuttleBuilder: NetworkImgLayer.heroFlightShuttleBuilder,
      child: image,
    );
  }
}

class _BannerCaption extends StatelessWidget {
  const _BannerCaption({required this.item});

  final BangumiItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = item.name != item.nameCn ? item.name : '';
    // 轮播文字叠在图片上，空间固定；放大字号会让整块被裁掉，
    // 这里限制到 1.25 倍，正文页面仍使用系统字号。
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.nameCn,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              shadows: const [
                Shadow(
                  blurRadius: 8,
                  color: Colors.black54,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
          ],
          if (item.ratingScore > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.star_rounded,
                  size: 15,
                  color: Color(0xFFFFC85C),
                ),
                const SizedBox(width: 3),
                Text(
                  item.ratingScore.toStringAsFixed(1),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.index,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final int count;
  final int index;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                width: i == index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == index ? activeColor : inactiveColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 横滑分区
// -----------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.onMore});

  final String title;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onMore != null)
            TextButton(
              onPressed: onMore,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: theme.colorScheme.onSurfaceVariant,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('查看更多'),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    super.key,
    required this.title,
    required this.items,
    required this.contentWidth,
    required this.onMore,
  });

  final String title;
  final List<BangumiItem> items;
  final double contentWidth;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    // 卡片宽度随可用宽度变化：手机 108，平板 132，桌面 148。
    final cardWidth = contentWidth < 600
        ? 108.0
        : contentWidth < 1000
            ? 132.0
            : 148.0;
    final edge = _contentPadding(contentWidth);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(edge + 4, 12, edge, 0),
          child: _SectionTitle(title: title, onMore: onMore),
        ),
        SizedBox(
          height: cardWidth / 0.65 + MediaQuery.textScalerOf(context).scale(34),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(edge, 0, edge, 0),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return SizedBox(
                width: cardWidth,
                child: BangumiCardV(bangumiItem: item, enableHero: false),
              );
            },
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 通用尺寸
// -----------------------------------------------------------------------------

/// 宽屏时内容居中，最大 1200；窄屏统一 12 的边距。
///
/// 用实际可用宽度（LayoutBuilder）而不是 MediaQuery：桌面端窗口被侧边栏
/// 占掉 76/260 像素，按窗口宽度算会把内容推得过窄。
double _contentPadding(double availableWidth) {
  return availableWidth <= 1224 ? 12 : (availableWidth - 1200) / 2 + 12;
}

double _contentWidth(BuildContext context, double availableWidth) =>
    availableWidth - _contentPadding(availableWidth) * 2;

// -----------------------------------------------------------------------------
// 网格（频道页与「大家都在看」共用）
// -----------------------------------------------------------------------------

class _BangumiGrid extends StatelessWidget {
  const _BangumiGrid({required this.items, required this.contentWidth});

  final List<BangumiItem> items;
  final double contentWidth;

  @override
  Widget build(BuildContext context) {
    // 注意：这里刻意不用 SliverLayoutBuilder——布局阶段的 builder 不参与
    // MobX 依赖追踪，数据到达后不会重建（表现为首屏空白、滚动后才出现）。
    // 宽度由外层 LayoutBuilder 传进来，既准确又保持依赖关系。
    final usable = _contentWidth(context, contentWidth);
    final crossCount = usable < 600
        ? 3
        : usable < 840
            ? 4
            : usable < 1100
                ? 5
                : 6;
    final cardWidth = usable / crossCount;
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        mainAxisSpacing: 10,
        crossAxisSpacing: 8,
        crossAxisCount: crossCount,
        mainAxisExtent:
            cardWidth / 0.65 + MediaQuery.textScalerOf(context).scale(34.0),
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        if (items.isEmpty) {
          return const BangumiCardSkeleton();
        }
        return BangumiCardV(bangumiItem: items[index], enableHero: false);
      }, childCount: items.isNotEmpty ? items.length : 12),
    );
  }
}

/// 首屏加载时的骨架卡片，保持与真实卡片一致的版面尺寸。
class BangumiCardSkeleton extends StatelessWidget {
  const BangumiCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: DecoratedBox(decoration: BoxDecoration(color: base))),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const SizedBox(height: 12, width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}
