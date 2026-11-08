import 'package:flutter/material.dart';

/// 服务端授予的称号徽标（例如「凉次元作者」）。
///
/// 称号只能由服务端下发，客户端不提供任何设置入口；[title] 为空时
/// 调用方应直接不渲染本组件。
///
/// 显示分级：
/// - [compact] = true：评论、讨论列表里跟昵称同一行（紧凑但醒目）
/// - [compact] = false：个人主页头部（大号、金色渐变、带光晕）
class AuthorTitleBadge extends StatelessWidget {
  const AuthorTitleBadge({
    super.key,
    required this.title,
    this.compact = true,
  });

  final String title;
  final bool compact;

  static const Color _goldDeep = Color(0xFF6B4300);
  static const Color _goldBorder = Color(0xFFB9810A);

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 13.0 : 17.0;
    final fontSize = compact ? 12.0 : 14.5;

    return Semantics(
      label: '称号：$title',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 13,
          vertical: compact ? 2 : 6,
        ),
        decoration: BoxDecoration(
          // 金色渐变区分「官方称号」，与「我的」「剧透」标签不混。
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD95C), Color(0xFFF0AE1B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _goldBorder, width: compact ? 1 : 1.5),
          boxShadow: compact
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x40F0AE1B),
                    blurRadius: 14,
                    offset: Offset(0, 3),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.workspace_premium_rounded,
              size: iconSize,
              color: _goldDeep,
            ),
            SizedBox(width: compact ? 4 : 5),
            Text(
              title,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: compact ? 0.2 : 0.6,
                color: _goldDeep,
                height: 1.2,
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 5),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF3C4),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
