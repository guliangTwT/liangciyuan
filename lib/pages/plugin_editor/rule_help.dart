import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';

/// 规则/番剧来源的使用说明。
///
/// 新用户最常见的两个问题：
/// 1. 不知道「规则」是什么，以为装完应用就能看；
/// 2. 搜索不到番剧时不知道是关键词问题、规则失效还是镜像没开。
///
/// 所以说明按「第一次用 → 搜不到 → 播放不了」三个真实场景组织，
/// 每条都给可点的操作入口，而不是只写概念。
class RuleHelpSheet extends StatelessWidget {
  const RuleHelpSheet({
    super.key,
    required this.onOpenCatalog,
    required this.onOpenManager,
    this.onOpenNetwork,
  });

  final VoidCallback onOpenCatalog;
  final VoidCallback onOpenManager;
  final VoidCallback? onOpenNetwork;

  /// 弹出说明面板（底部弹层，宽屏自动变成居中对话框）。
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onOpenCatalog,
    required VoidCallback onOpenManager,
    VoidCallback? onOpenNetwork,
  }) {
    return showAdaptiveBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      maxHeightFactor: 0.9,
      builder: (_) => RuleHelpSheet(
        onOpenCatalog: onOpenCatalog,
        onOpenManager: onOpenManager,
        onOpenNetwork: onOpenNetwork,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MaterialBottomSheetHeader(
          title: '番剧来源使用说明',
          description: '凉次元本身不提供片源，播放需要先装「规则」',
          onClose: () => Navigator.of(context).pop(),
        ),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              _HelpIntro(
                text: '规则 = 一个番剧网站 + 一套解析方式。应用把「番剧名」交给规则，'
                    '规则从那个网站取回可播放的剧集地址。所以：装好规则才能搜索和播放；'
                    '规则失效时换一条即可。',
              ),
              const SizedBox(height: 18),
              _HelpStep(
                index: 1,
                title: '装一条规则',
                body: '内置规则通常够用。想要更多站点，去「规则仓库」挑一个安装；'
                    '也可以粘贴别人分享的规则链接。',
                actions: [
                  _HelpAction(
                    label: '打开规则仓库',
                    icon: Icons.travel_explore_rounded,
                    filled: true,
                    onPressed: () {
                      Navigator.of(context).pop();
                      onOpenCatalog();
                    },
                  ),
                  _HelpAction(
                    label: '管理已装规则',
                    icon: Icons.extension_rounded,
                    onPressed: () {
                      Navigator.of(context).pop();
                      onOpenManager();
                    },
                  ),
                ],
              ),
              _HelpStep(
                index: 2,
                title: '搜索到番剧后，在「播放来源」里挑一条',
                body: '条目详情页点「开始观看」会同时用所有规则去搜，结果按来源分组。'
                    '哪个来源有结果、结果名对不对得上，一目了然；点一下就开始播放。',
                actions: const [],
              ),
              _HelpStep(
                index: 3,
                title: '搜不到？按这个顺序排查',
                body: '① 换一个检索词：用日文原名、简体/繁体译名或别名；'
                    '② 在来源菜单里「修改此来源的检索词」，只给这一条规则换词；'
                    '③ 查看规则是否显示「需要验证」，按提示完成网站验证；'
                    '④ 规则太久没更新可能已失效，去规则仓库更新或换一条。',
                actions: const [],
              ),
              _HelpStep(
                index: 4,
                title: '能搜到但播不了',
                body: '多数是网络或该站点本身的问题：先在来源菜单里「在浏览器中打开」'
                    '确认网站能访问；再检查网络设置里的加速与代理；'
                    '仍不行就换一个来源的结果。',
                actions: [
                  if (onOpenNetwork != null)
                    _HelpAction(
                      label: '打开网络设置',
                      icon: Icons.language_rounded,
                      onPressed: () {
                        Navigator.of(context).pop();
                        onOpenNetwork!();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '规则来自社区，内容由各站点自行提供，凉次元不存储任何视频文件。'
                        '收藏、观看记录与评论保存在你自己的账号里。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HelpIntro extends StatelessWidget {
  const _HelpIntro({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.onPrimaryContainer,
          height: 1.65,
        ),
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  const _HelpStep({
    required this.index,
    required this.title,
    required this.body,
    required this.actions,
  });

  final int index;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.65,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpAction extends StatelessWidget {
  const _HelpAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(minimumSize: const Size(0, 44));
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
    return filled
        ? FilledButton.tonal(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

/// 「播放来源」面板顶部的空状态：一条规则都没有时，不再让用户对着空白发愣。
class NoSourceGuide extends StatelessWidget {
  const NoSourceGuide({
    super.key,
    required this.onOpenCatalog,
    required this.onOpenHelp,
  });

  final VoidCallback onOpenCatalog;
  final VoidCallback onOpenHelp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.extension_off_rounded,
            size: 56,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '还没有可用的番剧来源',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '凉次元通过「规则」连接各个番剧网站。装一条规则后，'
            '就能搜索到剧集并开始播放。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onOpenCatalog,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.travel_explore_rounded),
            label: const Text('去规则仓库挑选'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onOpenHelp,
            child: const Text('先看看使用说明'),
          ),
        ],
      ),
    );
  }
}

/// 规则仓库顶部的一段说明条，回答「这些规则是干什么的」。
class RuleCatalogHint extends StatelessWidget {
  const RuleCatalogHint({super.key, required this.onHelp});

  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            Icons.help_outline_rounded,
            size: 20,
            color: colors.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '规则决定能从哪些网站获取番剧。装一到两条通常就够，装太多会拖慢搜索。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSecondaryContainer,
                height: 1.55,
              ),
            ),
          ),
          TextButton(
            onPressed: onHelp,
            style: TextButton.styleFrom(
              foregroundColor: colors.onSecondaryContainer,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('说明'),
          ),
        ],
      ),
    );
  }
}

/// 规则列表顶部：当前生效的规则数量与顺序提示。
class RuleManagerHint extends StatelessWidget {
  const RuleManagerHint({
    super.key,
    required this.count,
    required this.onHelp,
  });

  final int count;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count == 0
                  ? '还没有规则，先添加一条才能搜索番剧。'
                  : '$count 条规则已生效，拖动可调整搜索顺序。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: onHelp,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('使用说明'),
          ),
        ],
      ),
    );
  }
}

/// 首次进入规则仓库时的加载占位（带一句解释，避免用户以为卡住）。
class RuleCatalogLoading extends StatelessWidget {
  const RuleCatalogLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const LoadingIndicator(size: 36, semanticsLabel: '正在加载规则仓库'),
          const SizedBox(height: 16),
          Text(
            '正在加载规则仓库…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
