import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';

/// 启动阶段的加载页。
///
/// 之前这里是 `Scaffold(body: Container())`——纯空白，初始化较慢时用户会
/// 以为应用卡死。现在给一个低调的入场动画：Logo 呼吸 + 下方进度点，
/// 再叠一行状态文案（初始化各阶段会更新它）。
class StartupLoadingView extends StatefulWidget {
  const StartupLoadingView({super.key, this.status});

  /// 当前阶段文案，例如「正在准备番剧规则…」。
  final String? status;

  @override
  State<StartupLoadingView> createState() => _StartupLoadingViewState();
}

class _StartupLoadingViewState extends State<StartupLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 尊重「减弱动画」系统设置：关掉时保持静态，避免无谓的绘制。
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = widget.status;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = _controller.value;
            // 呼吸：0.94 ~ 1.02 的轻微缩放，配一圈随相位扩散的光环。
            final breath = 1 + math.sin(t * math.pi * 2) * 0.04;
            final glow = (math.sin(t * math.pi * 2) + 1) / 2;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 168,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 光环：透明度与半径随呼吸变化，不做无限放大以免刺眼。
                      Transform.scale(
                        scale: 0.72 + glow * 0.22,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.primary.withValues(
                              alpha: 0.06 + glow * 0.08,
                            ),
                          ),
                        ),
                      ),
                      Transform.scale(
                        scale: breath,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(26),
                          child: Image.asset(
                            'assets/images/logo/logo_rounded.png',
                            width: 92,
                            height: 92,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Icon(
                              Icons.play_circle_fill_rounded,
                              size: 76,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '凉次元',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '星轨番剧库',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                const LoadingIndicator(size: 28, semanticsLabel: '正在启动'),
                SizedBox(
                  // 固定高度，阶段文案切换时不会把整块内容顶得上下跳动。
                  height: 44,
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    child: status == null || status.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            key: ValueKey(status),
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              status,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
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
    );
  }
}
