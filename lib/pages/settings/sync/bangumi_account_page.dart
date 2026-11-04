import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/bean/widget/tonal_card.dart';
import 'package:kazumi/pages/settings/sync/sync_settings_widgets.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/storage/storage.dart';

/// Bangumi 账号绑定页。
///
/// 授权码只用于发表吐槽等需要账号的操作；收藏与观看记录已统一由 WebDAV 同步。
class BangumiAccountPage extends StatefulWidget {
  const BangumiAccountPage({super.key});

  @override
  State<BangumiAccountPage> createState() => _BangumiAccountPageState();
}

class _BangumiAccountPageState extends State<BangumiAccountPage> {
  final _tokenController = TextEditingController();
  bool _passwordVisible = false;
  bool _busy = false;
  bool _failed = false;
  String? _message;
  String? _tokenStatus;

  @override
  void initState() {
    super.initState();
    _tokenController.text = GStorage.getSetting(
      SettingsKeys.bangumiAccessToken,
    );
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  static String _describeError(Object error) {
    if (error is NetworkException) {
      switch (error.statusCode) {
        case 401:
          return 'Access Token 无效或已过期，请重新获取';
        case 403:
          return 'Bangumi 拒绝访问，请检查 Token 权限或稍后重试';
        case 429:
          return 'Bangumi 请求过于频繁，请稍后重试';
      }
      if (error.statusCode != null) {
        return 'Bangumi 服务请求失败（HTTP ${error.statusCode}），请稍后重试';
      }
      return error.message;
    }
    if (error is FormatException || error is TypeError) {
      return 'Bangumi 返回的账号信息格式异常，请稍后重试';
    }
    if (error is StateError) return error.message.toString();
    return 'Bangumi 操作失败，请稍后重试';
  }

  Future<void> _verifyAndSave() async {
    if (_busy) return;
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _failed = true;
        _message = '请填写 Access Token';
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _failed = false;
      _message = '正在验证…';
      _tokenStatus = null;
    });
    try {
      final user = await BangumiApi.getCurrentUser(accessToken: token);
      if (user == null) {
        throw StateError('无法获取账号信息，请确认授权码是否正确');
      }
      await GStorage.putSetting(SettingsKeys.bangumiAccessToken, token);
      if (!mounted) return;
      setState(() {
        _tokenController.text = token;
        _tokenStatus = '已连接 ${user.username}';
        _message = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = '${_describeError(e)}。修改未保存';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearToken() async {
    if (_busy) return;
    await GStorage.putSetting(SettingsKeys.bangumiAccessToken, '');
    if (!mounted) return;
    _tokenController.clear();
    setState(() {
      _tokenStatus = null;
      _failed = false;
      _message = '已清除授权码';
    });
  }

  Future<void> _getToken() async {
    bool opened;
    try {
      opened = await launchUrl(
        Uri.parse('https://next.bgm.tv/demo/access-token'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      setState(() {
        _failed = true;
        _message = '无法打开浏览器，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = GStorage.getSetting(
      SettingsKeys.bangumiAccessToken,
    ).trim().isNotEmpty;
    return PopScope(
      canPop: !_busy,
      child: SettingsDetailScaffold(
        title: const Text('Bangumi 账号'),
        body: SyncPageBody(
          maxWidth: 720,
          children: [
            const SyncPageIntro(
              icon: Icons.account_circle_rounded,
              title: 'Bangumi 账号',
              description:
                  '授权码仅用于在条目页发表吐槽等需要账号的操作。'
                  '收藏与观看记录已统一通过 WebDAV 同步，不再与 Bangumi 交换追番状态。'
                  'Bangumi 不开放账号密码登录，需要先在官网获取授权码。',
            ),
            TonalCard(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _tokenController,
                      obscureText: !_passwordVisible,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: 'Access Token',
                        hintText: '粘贴在 Bangumi 官网获取的授权码',
                        helperText: _tokenStatus,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _passwordVisible ? '隐藏授权码' : '显示授权码',
                          onPressed: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _busy ? null : _getToken,
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('获取授权码'),
                        ),
                        if (configured)
                          TextButton.icon(
                            onPressed: _busy ? null : _clearToken,
                            icon: const Icon(Icons.link_off_rounded, size: 18),
                            label: const Text('清除'),
                          ),
                        StateActionButton.tonal(
                          onPressed: _busy ? null : _verifyAndSave,
                          text: _busy ? '正在验证…' : '验证并保存',
                          icon: Icons.check_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_message != null)
              SyncFeedback(message: _message!, error: _failed, busy: _busy),
          ],
        ),
      ),
    );
  }
}
