import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 启动页。
///
/// 之前这里是纯空白；后来加了一个静态 Logo + 转圈，但初始化往往不到一秒，
/// 动画还没来得及展开就跳走了，等于没有。
///
/// 现在的做法：
/// 1. **入场**：Logo 从略小、略透明开始，带一点回弹地放大到位；
/// 2. **待机**：一圈极细的弧线缓慢环绕（不是转圈加载条，只是呼吸感），
///    外加一层很淡的光晕随节奏明暗；
/// 3. **收尾**：整块内容轻微上浮、淡出，交给下一页，不是硬切。
///
/// 全程只用单色 + 透明度，没有渐变网格、没有粒子——保持极简，
/// 但确实「有东西在看」。
class StartupLoadingView extends StatefulWidget {
  const StartupLoadingView({
    super.key,
    this.status,
    this.leaving = false,
  });

  /// 当前阶段文案，例如「正在准备番剧规则…」。
  final String? status;

  /// 置为 true 时播放退场动画（上浮 + 淡出）。由调用方在跳转前切换。
  final bool leaving;

  @override
  State<StartupLoadingView> createState() => _StartupLoadingViewState();
}

class _StartupLoadingViewState extends State<StartupLoadingView>
    with TickerProviderStateMixin {
  /// 入场：0 → 1，带 overshoot。
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 780),
  );

  /// 待机循环：缓慢呼吸与环绕。
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  /// 退场。
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void initState() {
    super.initState();
    _enter.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 尊重系统「减弱动画」：直接停在终态，不做任何循环。
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _enter.value = 1;
      _idle.stop();
      _exit.value = widget.leaving ? 1 : 0;
      return;
    }
    if (!_idle.isAnimating) {
      _idle.repeat();
    }
    if (widget.leaving && !_exit.isAnimating && _exit.value == 0) {
      _exit.forward();
    }
  }

  @override
  void didUpdateWidget(covariant StartupLoadingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.leaving && !oldWidget.leaving) {
      _exit.forward();
    } else if (!widget.leaving && oldWidget.leaving) {
      _exit.reverse();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _idle.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: AnimatedBuilder(
        animation: Listenable.merge([_enter, _idle, _exit]),
        builder: (context, _) {
          // 入场：从 0.82 倍放大到 1，用 easeOutBack 给一点回弹。
          final enterT = Curves.easeOutCubic.transform(_enter.value);
          final scaleIn = 0.82 + 0.18 * enterT;
          final fadeIn = enterT;

          // 待机：正弦呼吸，幅度很小，避免"一鼓一鼓"。
          final idlePhase = _idle.value * math.pi * 2;
          final breath = 1 + math.sin(idlePhase) * 0.012;
          final glow = (math.sin(idlePhase) + 1) / 2;

          // 退场：上浮 12 像素并淡出。
          final exitT = Curves.easeInCubic.transform(_exit.value);
          final lift = -12.0 * exitT;
          final opacity = (1 - exitT) * fadeIn;

          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, lift),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LogoMark(
                      scale: scaleIn * breath,
                      glow: glow,
                      enterT: enterT,
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '凉次元',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '星轨番剧库',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 34),
                    // 细线进展：宽度随待机节奏轻微伸缩，暗示还在处理。
                    SizedBox(
                      width: 92,
                      child: _PulseLine(phase: idlePhase, progress: enterT),
                    ),
                    SizedBox(
                      height: 46,
                      child: AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 240),
                        child: _StatusText(
                          key: ValueKey(widget.status ?? ''),
                          text: widget.status,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Logo + 一圈缓慢环绕的细弧 + 呼吸光晕。
class _LogoMark extends StatelessWidget {
  const _LogoMark({
    required this.scale,
    required this.glow,
    required this.enterT,
  });

  final double scale;
  final double glow;
  final double enterT;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 148,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 光晕：只做明暗，不放大，避免"水波纹"式的廉价感。
          Opacity(
            opacity: (0.05 + glow * 0.09) * enterT,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary,
              ),
            ),
          ),
          // 环绕细弧：单段 60° 弧，绕中心缓慢转动。
          Opacity(
            opacity: 0.55 * enterT,
            child: _SpinningArc(
              color: colors.primary,
              phase: glow,
            ),
          ),
          Transform.scale(
            scale: scale,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                'assets/images/logo/logo_rounded.png',
                width: 88,
                height: 88,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.play_circle_fill_rounded,
                  size: 72,
                  color: colors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一段绕中心旋转的细弧。rotation 由外部 phase 驱动，保持与呼吸同频。
class _SpinningArc extends StatelessWidget {
  const _SpinningArc({required this.color, required this.phase});

  final Color color;
  final double phase;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: phase * math.pi * 2,
      child: CustomPaint(
        size: const Size.square(124),
        painter: _ArcPainter(color: color),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.85),
          color.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.16, 0.32],
      ).createShader(rect);
    // 起始角 -pi/2 让弧线从顶部开始，视觉上更稳。
    canvas.drawArc(
      rect.deflate(1),
      -math.pi / 2,
      math.pi * 2,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) => oldDelegate.color != color;
}

/// 一根细线的呼吸：中间亮、两端虚。
class _PulseLine extends StatelessWidget {
  const _PulseLine({required this.phase, required this.progress});

  final double phase;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // 0.6 ~ 1.0 之间伸缩，最小也保底可见。
    final width = 92 * (0.6 + 0.4 * ((math.sin(phase) + 1) / 2));
    return SizedBox(
      width: 92,
      height: 2,
      child: Align(
        alignment: Alignment.center,
        child: Opacity(
          opacity: 0.75 * progress,
          child: Container(
            width: width,
            height: 2,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({super.key, required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = text ?? '';
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
