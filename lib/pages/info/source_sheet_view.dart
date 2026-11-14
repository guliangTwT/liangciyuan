part of 'source_sheet.dart';

class _SourceSearchGroup {
  const _SourceSearchGroup({
    required this.name,
    required this.keyword,
    required this.status,
    required this.results,
  });

  final String name;
  final String keyword;
  final PluginSearchStatus status;
  final List<SearchItem> results;

  bool get isSearching => status == PluginSearchStatus.pending;
  bool get hasResults =>
      status == PluginSearchStatus.success && results.isNotEmpty;

  /// 还没出结论的来源。它们在「其他来源」里也要显示「检索中」。
  bool get isPending => status == PluginSearchStatus.pending;

  /// 有结果或仍在检索：这些默认展开；已经确定为无结果/失败的收进折叠区，
  /// 免得十几个规则把面板撑得很长。
  bool get isPrimary => hasResults || isPending;

  String get statusLabel => switch (status) {
        PluginSearchStatus.pending => '检索中…',
        PluginSearchStatus.success =>
          results.isEmpty ? '无结果' : '${results.length} 个结果',
        PluginSearchStatus.noResult => '无结果',
        PluginSearchStatus.error => '检索失败',
        PluginSearchStatus.captcha => '需要验证',
      };
}

enum _SourceDisplay { preview, expanded, collapsed }

class _SourceSheetView extends StatefulWidget {
  const _SourceSheetView({
    required this.keyword,
    required this.groups,
    required this.firstResultSource,
    required this.onSourceSearch,
    required this.onSourceAliasSearch,
    required this.onRetry,
    required this.onVerify,
    required this.onOpenBrowser,
    required this.onPlay,
    required this.onClose,
    required this.onOpenHelp,
    this.onOpenCatalog,
  });

  final String keyword;
  final List<_SourceSearchGroup> groups;
  final String? firstResultSource;
  final ValueChanged<String> onSourceSearch;
  final ValueChanged<String> onSourceAliasSearch;
  final ValueChanged<String> onRetry;
  final ValueChanged<String> onVerify;
  final ValueChanged<String> onOpenBrowser;
  final void Function(String sourceName, SearchItem result) onPlay;
  final VoidCallback onClose;
  final VoidCallback onOpenHelp;

  /// 没有任何规则时的入口。
  final VoidCallback? onOpenCatalog;

  @override
  State<_SourceSheetView> createState() => _SourceSheetViewState();
}

class _SourceSheetViewState extends State<_SourceSheetView> {
  final _scrollController = ScrollController();
  final _display = <String, _SourceDisplay>{};
  final _headerKeys = <String, GlobalKey>{};
  bool _autoExpansionHandled = false;
  bool _showOtherSources = false;

  @override
  void initState() {
    super.initState();
    _autoExpandFirstResult();
  }

  @override
  void didUpdateWidget(covariant _SourceSheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final names = widget.groups.map((group) => group.name).toSet();
    _display.removeWhere((name, _) => !names.contains(name));
    _headerKeys.removeWhere((name, _) => !names.contains(name));
    _autoExpandFirstResult();
  }

  void _autoExpandFirstResult() {
    final name = widget.firstResultSource;
    if (_autoExpansionHandled || name == null) return;
    _autoExpansionHandled = true;
    _display[name] = _SourceDisplay.preview;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _setDisplay(String name, _SourceDisplay display) {
    setState(() {
      _autoExpansionHandled = true;
      _display[name] = display;
    });
  }

  void _collapseFromFooter(String name) {
    final headerContext = _headerKeys[name]?.currentContext;
    if (headerContext != null) {
      // Anchor before shrinking, while the header is still laid out.
      Scrollable.ensureVisible(headerContext, alignment: 0);
    }
    _setDisplay(name, _SourceDisplay.collapsed);
  }

  Widget _animateSize(Widget child) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: splitListMotionDuration,
          curve: splitListMotionCurve,
          alignment: Alignment.topCenter,
          child: child,
        );

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            MaterialBottomSheetHeader(
              title: '播放来源',
              description: '还没有安装任何规则',
              compact: true,
              onClose: widget.onClose,
            ),
            Expanded(
              child: NoSourceGuide(
                onOpenCatalog: widget.onOpenCatalog ??
                    () => context.pushNamed('/settings/plugin/shop'),
                onOpenHelp: widget.onOpenHelp,
              ),
            ),
          ],
        ),
      );
    }

    final pending = widget.groups.where((group) => group.isSearching).length;
    final withResults =
        widget.groups.where((group) => group.hasResults).toList();
    final resultCount =
        withResults.fold(0, (sum, group) => sum + group.results.length);
    final primary = widget.groups.where((group) => group.isPrimary).toList();
    final others = widget.groups.where((group) => !group.isPrimary).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          MaterialBottomSheetHeader(
            title: '播放来源',
            description: pending > 0
                ? '检索中 ${widget.groups.length - pending}/${widget.groups.length} · $resultCount 个结果'
                : '${widget.groups.length} 个来源 · $resultCount 个结果',
            compact: true,
            onClose: widget.onClose,
          ),
          if (pending == 0 && withResults.isEmpty)
            _NoResultBar(
              keyword: widget.keyword,
              sourceCount: widget.groups.length,
              onHelp: widget.onOpenHelp,
            )
          else if (withResults.isNotEmpty)
            _BestSourceBar(
              best: withResults.first,
              total: resultCount,
              onPlay: () => widget.onPlay(
                withResults.first.name,
                withResults.first.results.first,
              ),
            ),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.builder(
                      itemCount: primary.length,
                      findChildIndexCallback: (key) {
                        final index = primary
                            .indexWhere((group) => ValueKey(group.name) == key);
                        return index < 0 ? null : index;
                      },
                      itemBuilder: (context, index) {
                        final group = primary[index];
                        return Padding(
                          key: ValueKey(group.name),
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildSourceGroup(group),
                        );
                      },
                    ),
                  ),
                  if (others.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: _OtherSourcesSection(
                          groups: others,
                          expanded: _showOtherSources,
                          onToggle: () => setState(
                            () => _showOtherSources = !_showOtherSources,
                          ),
                          builder: _buildSourceGroup,
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _SourceFooter(onHelp: widget.onOpenHelp),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SafeArea(top: false, child: SizedBox(height: 24)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceGroup(_SourceSearchGroup group) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final display = _display[group.name] ?? _SourceDisplay.collapsed;
    final collapsed = display == _SourceDisplay.collapsed;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : splitListMotionDuration;

    void toggle() => _setDisplay(
          group.name,
          collapsed ? _SourceDisplay.preview : _SourceDisplay.collapsed,
        );

    // 状态点：有结果用主色，检索中用次要色，失败/无结果用弱色。
    final (dotColor, statusText) = switch (group.status) {
      PluginSearchStatus.success when group.results.isNotEmpty => (
          colors.primary,
          group.statusLabel,
        ),
      PluginSearchStatus.pending => (colors.secondary, group.statusLabel),
      PluginSearchStatus.captcha => (colors.tertiary, group.statusLabel),
      _ => (colors.outline, group.statusLabel),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: _headerKeys.putIfAbsent(group.name, GlobalKey.new),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  button: true,
                  expanded: !collapsed,
                  label: '来源规则：${group.name}，${group.statusLabel}',
                  onTap: toggle,
                  excludeSemantics: true,
                  child: Material(
                    color: group.hasResults
                        ? colors.surfaceContainerHigh
                        : colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: toggle,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 52),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  group.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: group.hasResults
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                statusText,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: group.hasResults
                                      ? colors.primary
                                      : colors.onSurfaceVariant,
                                  fontWeight: group.hasResults
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              const SizedBox(width: 4),
                              AnimatedRotation(
                                turns: collapsed ? 0 : 0.5,
                                duration: duration,
                                curve: splitListMotionCurve,
                                child: Icon(
                                  Icons.expand_more_rounded,
                                  size: 20,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildSourceMenu(group),
            ],
          ),
        ),
        if (!collapsed && group.keyword != widget.keyword)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 12, 0),
            child: Text(
              '检索词：${group.keyword}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        _animateSize(
          collapsed
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _buildSourceBody(
                    group,
                    showAll: display == _SourceDisplay.expanded,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSourceBody(_SourceSearchGroup group, {required bool showAll}) {
    if (!group.hasResults) {
      return SplitListRow(
        topRadius: splitListOuterRadius,
        bottomRadius: splitListOuterRadius,
        child: switch (group.status) {
          PluginSearchStatus.pending => _buildSearching(),
          PluginSearchStatus.success ||
          PluginSearchStatus.noResult =>
            GeneralEmptyState(
              icon: Icons.search_off_rounded,
              title: '没有找到匹配结果',
              compact: true,
              actions: [
                StateActionButton.tonal(
                  onPressed: () => widget.onSourceSearch(group.name),
                  text: '换个检索词',
                ),
                TextButton(
                  onPressed: () => widget.onSourceAliasSearch(group.name),
                  child: const Text('使用别名'),
                ),
              ],
            ),
          PluginSearchStatus.captcha =>
            _buildSourceIssue(group.name, requiresVerification: true),
          PluginSearchStatus.error =>
            _buildSourceIssue(group.name, requiresVerification: false),
        },
      );
    }

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final visibleCount = showAll ? group.results.length : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < visibleCount; index++) ...[
          if (index > 0) const SizedBox(height: splitListRowGap),
          _buildResult(group, index),
        ],
        if (group.results.length > 1) ...[
          const SizedBox(height: splitListRowGap),
          SplitListRow(
            bottomRadius: splitListOuterRadius,
            onTap: () => showAll
                ? _collapseFromFooter(group.name)
                : _setDisplay(group.name, _SourceDisplay.expanded),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        showAll ? '收起全部条目' : '展开全部 ${group.results.length} 个结果',
                        textAlign: TextAlign.center,
                        style:
                            theme.textTheme.labelLarge?.copyWith(color: primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      showAll
                          ? Icons.unfold_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSourceMenu(_SourceSearchGroup group) => TooltipVisibility(
        visible: false,
        child: KazumiMenuButton(
          animated: true,
          builder: (context, toggle) => IconButton(
            tooltip: '${group.name} 的更多操作',
            icon: const Icon(Icons.more_horiz_rounded, size: 20),
            onPressed: toggle,
          ),
          menuChildren: [
            KazumiMenuItem(
              label: '修改此来源的检索词',
              onPressed: () => widget.onSourceSearch(group.name),
            ),
            KazumiMenuItem(
              label: '使用别名检索此来源',
              onPressed: () => widget.onSourceAliasSearch(group.name),
            ),
            KazumiMenuItem(
              label: '重新检索此来源',
              onPressed: () => widget.onRetry(group.name),
            ),
            KazumiMenuItem(
              label: '在浏览器中打开',
              onPressed: () => widget.onOpenBrowser(group.name),
            ),
          ],
        ),
      );

  Widget _buildResult(_SourceSearchGroup group, int index) {
    final theme = Theme.of(context);
    final result = group.results[index];
    return SplitListRow(
      topRadius: index == 0 ? splitListOuterRadius : splitListInnerRadius,
      bottomRadius: group.results.length == 1
          ? splitListOuterRadius
          : splitListInnerRadius,
      onTap: () => widget.onPlay(group.name, result),
      child: Semantics(
        button: true,
        label: '播放 ${result.name}，来源 ${group.name}',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    result.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.play_arrow_rounded,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearching() => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const LoadingIndicator(size: 20, semanticsLabel: '正在检索'),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '正在检索…',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildSourceIssue(
    String sourceName, {
    required bool requiresVerification,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, title, hint, action, onAction) = requiresVerification
        ? (
            Icons.verified_user_outlined,
            '需要验证',
            '该站点要求先完成人机验证，验证后会自动继续检索。',
            '进行验证',
            () => widget.onVerify(sourceName),
          )
        : (
            Icons.error_outline_rounded,
            '检索失败',
            '可能是站点暂时不可用或网络被拦截。可以重试，或换一个来源。',
            '重试',
            () => widget.onRetry(sourceName),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  icon,
                  size: 20,
                  color: requiresVerification
                      ? colors.onSurfaceVariant
                      : colors.error,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonal(onPressed: onAction, child: Text(action)),
              TextButton(
                onPressed: () => widget.onOpenBrowser(sourceName),
                child: const Text('打开网站'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 顶部「最佳来源」快捷条：一键播放第一个有结果的第一条。
///
/// 多数情况下来源之间的第一条结果就是同一部番，用户不需要逐个展开比较。
class _BestSourceBar extends StatelessWidget {
  const _BestSourceBar({
    required this.best,
    required this.total,
    required this.onPlay,
  });

  final _SourceSearchGroup best;
  final int total;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Material(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPlay,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Icon(
                  Icons.play_circle_fill_rounded,
                  size: 26,
                  color: colors.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '直接播放',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        best.results.first.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '来源 ${best.name} · 共 $total 个结果',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onPrimaryContainer.withValues(
                            alpha: 0.75,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: colors.onPrimaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 所有来源都没有结果时的提示条。
class _NoResultBar extends StatelessWidget {
  const _NoResultBar({
    required this.keyword,
    required this.sourceCount,
    required this.onHelp,
  });

  final String keyword;
  final int sourceCount;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 22,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$sourceCount 个来源都没有搜到「$keyword」。试试更短的片名、日文原名，'
                '或在单个来源上用别名检索。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
            TextButton(onPressed: onHelp, child: const Text('怎么办')),
          ],
        ),
      ),
    );
  }
}

/// 无结果/失败的来源收在这里，默认折叠。
class _OtherSourcesSection extends StatelessWidget {
  const _OtherSourcesSection({
    required this.groups,
    required this.expanded,
    required this.onToggle,
    required this.builder,
  });

  final List<_SourceSearchGroup> groups;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget Function(_SourceSearchGroup group) builder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.filter_alt_off_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        expanded
                            ? '收起没搜到结果的 ${groups.length} 个来源'
                            : '其他 ${groups.length} 个来源没有结果',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : splitListMotionDuration,
                      curve: splitListMotionCurve,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final group in groups)
                  Padding(
                    key: ValueKey('other-${group.name}'),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: builder(group),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 面板底部的一行帮助入口。
class _SourceFooter extends StatelessWidget {
  const _SourceFooter({required this.onHelp});

  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            '来源规则由社区维护，站点可用性会变化。',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: onHelp,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: const Text('使用说明'),
        ),
      ],
    );
  }
}
