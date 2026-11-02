import 'package:flutter/material.dart';
import 'package:kazumi/pages/onboarding/onboarding_step_layout.dart';

class UpdateSourceStep extends StatelessWidget {
  const UpdateSourceStep({
    super.key,
    required this.useGithubUpdate,
    required this.onChanged,
  });

  /// 仅有一个官方发布渠道（GitHub Releases），因此本步骤只控制
  /// 是否启用应用内自动检查更新；关闭后仍可随时手动检查。
  final bool useGithubUpdate;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => OnboardingStepLayout(
    leading: const OnboardingStepIcon(
      icon: Icons.system_update_rounded,
      shape: OnboardingIconShape.cookie,
    ),
    title: '保持最新',
    subtitle: '选择是否让凉次元自动检查新版本。',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AutoUpdateCard(
          selected: useGithubUpdate,
          onChanged: onChanged,
        ),
        const SizedBox(height: 12),
        const OnboardingHint(text: '之后也可以在 关于 → 自动检查更新 中修改。'),
      ],
    ),
  );
}

class _AutoUpdateCard extends StatelessWidget {
  const _AutoUpdateCard({
    required this.selected,
    required this.onChanged,
  });

  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = selected ? colors.onSecondaryContainer : colors.onSurface;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubicEmphasized,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: selected ? colors.secondaryContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(selected ? 20 : 28),
        border: Border.all(
          color: selected ? colors.secondary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          value: selected,
          onChanged: onChanged,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          secondary: Icon(Icons.rocket_launch_rounded, size: 28, color: foreground),
          title: Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '应用内自动更新',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: ShapeDecoration(
                  color: colors.tertiaryContainer,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  '推荐',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '新版本通过 GitHub Releases 发布，开启后将自动检查并可在应用内下载安装；关闭后仍可随时在 设置 → 关于 手动检查。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: selected ? foreground : colors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
