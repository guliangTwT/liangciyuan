import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/pages/web_portal/web_portal_page.dart';
import 'package:kazumi/services/storage/storage.dart';

/// Default URL lives beside the portal page so the settings UI cannot drift
/// from the real fallback.

class WebPortalSettingsPage extends StatefulWidget {
  const WebPortalSettingsPage({super.key});

  @override
  State<WebPortalSettingsPage> createState() => _WebPortalSettingsPageState();
}

class _WebPortalSettingsPageState extends State<WebPortalSettingsPage> {
  late String _url;
  late String _sites;

  @override
  void initState() {
    super.initState();
    _url = _storedUrl();
    _sites = GStorage.getSetting(SettingsKeys.webPortalSites);
  }

  String _storedUrl() {
    final value = GStorage.getSetting(SettingsKeys.webPortalUrl).trim();
    return value.isEmpty ? kDefaultWebPortalUrl : value;
  }

  Future<void> _editHome() async {
    final controller = TextEditingController(text: _url);
    final value = await KazumiDialog.show<String>(
      builder: (context) => AlertDialog(
        title: const Text('默认网页'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('应用内网页入口默认打开这个地址。'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: kDefaultWebPortalUrl,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    final normalized = _normalize(value);
    if (!_isHttpUrl(normalized)) {
      KazumiDialog.showToast(message: '请输入 http:// 或 https:// 地址');
      return;
    }
    await GStorage.putSetting(SettingsKeys.webPortalUrl, normalized);
    if (!mounted) return;
    setState(() => _url = normalized);
    KazumiDialog.showToast(message: '默认网页已保存');
  }

  Future<void> _restoreDefault() async {
    await GStorage.putSetting(SettingsKeys.webPortalUrl, kDefaultWebPortalUrl);
    if (!mounted) return;
    setState(() => _url = kDefaultWebPortalUrl);
    KazumiDialog.showToast(message: '已恢复默认网页');
  }

  Future<void> _editSites() async {
    final controller = TextEditingController(text: _sites);
    final value = await KazumiDialog.show<String>(
      builder: (context) => AlertDialog(
        title: const Text('备用网页'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('每行一个网址；它们会出现在网页页的「切换网页」菜单中。'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 4,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'https://example.com\nhttps://another.example.com',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    final lines = [
      for (final line in value.split(RegExp(r'[\r\n,，]+')))
        if (line.trim().isNotEmpty) _normalize(line),
    ];
    final invalid = lines.where((line) => !_isHttpUrl(line)).toList();
    if (invalid.isNotEmpty) {
      KazumiDialog.showToast(message: '有无效地址，请使用 http:// 或 https://');
      return;
    }
    final stored = lines.join('\n');
    await GStorage.putSetting(SettingsKeys.webPortalSites, stored);
    if (!mounted) return;
    setState(() => _sites = stored);
    KazumiDialog.showToast(message: '备用网页已保存');
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('网页设置'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('内置网页'),
            tiles: [
              SettingsTile(
                leading: Icons.language_rounded,
                title: const Text('默认网页'),
                description: Text(_url),
                trailing: const Icon(Icons.edit_rounded, size: 20),
                onPressed: (_) => _editHome(),
              ),
              SettingsTile(
                leading: Icons.travel_explore_rounded,
                title: const Text('备用网页'),
                description: Text(
                  _sites.trim().isEmpty
                      ? '尚未添加，每行一个网址'
                      : '已添加 ${parseWebPortalSites(_sites).length} 个',
                ),
                trailing: const Icon(Icons.edit_rounded, size: 20),
                onPressed: (_) => _editSites(),
              ),
              SettingsTile(
                leading: Icons.restart_alt_rounded,
                title: const Text('恢复默认网页'),
                description: Text(kDefaultWebPortalUrl),
                onPressed: (_) => _restoreDefault(),
              ),
              SettingsTile(
                leading: Icons.open_in_browser_rounded,
                title: const Text('打开内置网页'),
                onPressed: (_) => context.pushNamed('/web/'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _normalize(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return value;
  if (!value.contains('://')) value = 'https://$value';
  return value;
}

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}
