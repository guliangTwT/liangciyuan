import 'package:flutter/material.dart';
import 'package:kazumi/pages/onboarding/onboarding_step_layout.dart';
import 'package:kazumi/pages/plugin_editor/plugin_catalog_view.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

class PluginShopStep extends StatelessWidget {
  const PluginShopStep({
    super.key,
    required this.controller,
  });

  final PluginsController controller;

  @override
  Widget build(BuildContext context) => PluginCatalogView.onboarding(
        controller: controller,
        builder: (context, slivers) => OnboardingStepLayout.slivers(
          leading: const OnboardingStepIcon(
            icon: Icons.extension_rounded,
            shape: OnboardingIconShape.flower,
          ),
          title: '添加番剧来源',
          subtitle: '已内置 giriGiriLove 规则，可直接开始观看；也可以再添加其他站点。',
          slivers: slivers,
        ),
      );
}
