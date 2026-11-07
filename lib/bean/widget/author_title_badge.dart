import 'package:flutter/material.dart';

/// 服务端授予的称号徽标（例如「凉次元作者」）。
///
/// 称号只能由服务端下发，客户端不提供任何设置入口；[title] 为空时
/// 调用方应直接不渲染本组件。
class AuthorTitleBadge extends StatelessWidget {
  const AuthorTitleBadge({
    super.key,
    required this.title,
    this.compact = true,
  });

  final String title;

  /// 紧凑模式（列表卡片里）用更小的字号与内边距。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // 用金色系区分「官方称号」与普通标签（我的/剧透）。
    final background = colors.tertiaryContainer;
    final foreground = colors.onTertiaryContainer;
    return Semantics(
      label: '称号：$title',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 1 : 2,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
          border: Border(
            left: BorderSide(color: colors.tertiary, width: 2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_rounded,
              size: compact ? 11 : 13,
              color: foreground,
            ),
            const SizedBox(width: 3),
            Text(
              title,
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
