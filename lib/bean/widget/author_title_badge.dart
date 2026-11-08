import 'package:flutter/material.dart';

/// 服务端授予的称号徽标（例如「凉次元作者」）。
///
/// 称号只能由服务端下发，客户端不提供任何设置入口；[title] 为空时
/// 调用方应直接不渲染本组件。
///
/// 视觉上刻意克制：一个细边框的胶囊 + 一枚图标 + 文字，不加渐变、
/// 不加光晕、不加多余圆点——称号要"看得见"，但不该比昵称更抢眼。
/// - [compact] = true：评论/讨论列表，与昵称同处一行
/// - [compact] = false：个人主页头部，字号与内边距更大
class AuthorTitleBadge extends StatelessWidget {
  const AuthorTitleBadge({
    super.key,
    required this.title,
    this.compact = true,
  });

  final String title;
  final bool compact;

  /// 深琥珀色：在浅色与深色主题下都有足够对比度。
  static const Color _ink = Color(0xFF8A5A00);
  static const Color _border = Color(0xFFD9A020);
  static const Color _fill = Color(0x1FD9A020);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFFFD98A) : _ink;
    final border = dark ? const Color(0x66FFD98A) : _border;
    final fill = dark ? const Color(0x1AFFD98A) : _fill;

    return Semantics(
      label: '称号：$title',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 10,
          vertical: compact ? 1.5 : 4,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_rounded,
              size: compact ? 12 : 15,
              color: ink,
            ),
            SizedBox(width: compact ? 3 : 5),
            Text(
              title,
              style: TextStyle(
                fontSize: compact ? 11 : 13,
                fontWeight: FontWeight.w600,
                height: 1.25,
                letterSpacing: 0.2,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
