import 'package:flutter/material.dart';
import 'package:kazumi/pages/menu/menu.dart';
import 'package:kazumi/services/deep_links/app_deep_links.dart';
import 'package:kazumi/services/storage/storage.dart';

class IndexPage extends StatefulWidget {
  const IndexPage({super.key, required this.location});

  final String location;

  @override
  State<IndexPage> createState() => _IndexPageState();
}

class _IndexPageState extends State<IndexPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Startup and onboarding both end here; earlier pushes would be cleared.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppDeepLinks().markReady();
      _showUpstreamAttribution();
    });
  }

  Future<void> _showUpstreamAttribution() async {
    if (GStorage.getSetting(SettingsKeys.upstreamAttributionShown) ||
        !mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            'assets/images/logo/logo_rounded.png',
            width: 56,
            height: 56,
            fit: BoxFit.cover,
          ),
        ),
        title: const Text('关于凉次元'),
        content: const Text(
          '本软件改编自 Kazumi 开源项目。感谢原作者 Predidit 与所有贡献者的持续维护和无私分享。凉次元在此基础上进行了品牌与界面改造，并继续遵循 GNU GPL-3.0 许可证。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('开始使用'),
          ),
        ],
      ),
    );
    await GStorage.putSetting(SettingsKeys.upstreamAttributionShown, true);
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMenu(location: widget.location);
  }
}
