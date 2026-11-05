import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/settings/sync/sync_settings_widgets.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/services/account/account_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/webdav.dart';
import 'package:kazumi/services/sync/webdav_auto_sync.dart';
import 'package:kazumi/services/sync/danmaku_shield_sync_service.dart';
import 'package:kazumi/bean/settings/settings_dropdown_tile.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _nickname = TextEditingController();
  final _account = AccountService();

  bool _registerMode = false;
  bool _busy = false;
  bool _failed = false;
  bool _obscure = true;
  String? _message;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _account.ensureLoaded();
    _account.addListener(_onAccountChanged);
  }

  @override
  void dispose() {
    _account.removeListener(_onAccountChanged);
    _timer?.cancel();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    _nickname.dispose();
    super.dispose();
  }

  void _onAccountChanged() {
    if (mounted) setState(() {});
  }

  bool _looksLikeQqMail(String value) {
    return RegExp(
      r'^[\w.+-]+@(qq\.com|vip\.qq\.com|foxmail\.com)$',
      caseSensitive: false,
    ).hasMatch(value.trim());
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown -= 1);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!_looksLikeQqMail(email)) {
      setState(() {
        _failed = true;
        _message = '请填写 QQ 邮箱（@qq.com / @foxmail.com）';
      });
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
      _message = '正在发送验证码…';
    });
    try {
      await _account.sendCode(email);
      if (!mounted) return;
      _startCooldown();
      setState(() => _message = '验证码已发送，请查收 QQ 邮箱');
    } on AccountException catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = '操作失败：$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!_looksLikeQqMail(email)) {
      setState(() {
        _failed = true;
        _message = '请填写 QQ 邮箱（@qq.com / @foxmail.com）';
      });
      return;
    }
    if (_password.text.length < 8) {
      setState(() {
        _failed = true;
        _message = '密码至少 8 位';
      });
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
      _message = _registerMode ? '正在注册…' : '正在登录…';
    });
    try {
      if (_registerMode) {
        await _account.register(
          email: email,
          code: _code.text.trim(),
          password: _password.text,
          nickname: _nickname.text.trim().isEmpty
              ? '凉次元用户'
              : _nickname.text.trim(),
        );
      } else {
        await _account.login(email: email, password: _password.text);
      }
      if (!mounted) return;
      setState(() {
        _message = _registerMode ? '注册成功' : '登录成功';
        _failed = false;
        _password.clear();
        _code.clear();
      });
    } on AccountException catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = '操作失败：$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showResetPasswordDialog() async {
    final resetDone = await showDialog<String>(
      context: context,
      builder: (_) => _ResetPasswordDialog(initialEmail: _email.text.trim()),
    );
    if (!mounted || resetDone == null) return;
    setState(() {
      _failed = false;
      _message = '密码已重置，请用新密码登录';
    });
  }

  Future<void> _syncNow() async {
    final account = _account..ensureLoaded();
    if (!account.loggedIn) {
      setState(() {
        _failed = true;
        _message = '请先登录凉次元账号';
      });
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
      _message = '正在同步…';
    });
    try {
      final sync = WebDav();
      if (!sync.initialized) await sync.init();
      if (GStorage.getSetting(SettingsKeys.webDavEnableHistory)) {
        await sync.syncHistory();
      }
      if (GStorage.getSetting(SettingsKeys.webDavEnableCollect)) {
        await sync.syncCollectibles();
        inject<CollectController>().loadCollectibles();
      }
      await inject<DanmakuShieldSyncService>().syncIfEnabled();
      if (mounted) setState(() => _message = '同步完成');
    } on AccountException catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = '同步失败：$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editNickname() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _NicknameDialog(initial: _account.nickname),
    );
    if (value == null || value.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _failed = false;
      _message = '正在保存…';
    });
    try {
      await _account.updateNickname(value);
      if (mounted) setState(() => _message = '昵称已更新');
    } on AccountException catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAvatar() async {
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = '无法打开相册：$e';
        });
      }
      return;
    }
    if (picked == null || !mounted) return;
    setState(() {
      _busy = true;
      _failed = false;
      _message = '正在上传头像…';
    });
    try {
      await _account.uploadAvatar(picked.path);
      if (mounted) setState(() => _message = '头像已更新');
    } on AccountException catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = e.message;
        });
      }
    } catch (e) {
      // 文件可能已被系统清理或无权读取（FileSystemException 等）。
      if (mounted) {
        setState(() {
          _failed = true;
          _message = '头像上传失败：$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后本机不会删除收藏与观看记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _account.logout();
    if (!mounted) return;
    setState(() {
      _message = '已退出登录';
      _failed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    _account.ensureLoaded();
    return PopScope(
      canPop: !_busy,
      child: SettingsDetailScaffold(
        title: const Text('账号与云同步'),
        body: SyncPageBody(
          maxWidth: 720,
          children: [
            const SyncPageIntro(
              icon: Icons.account_circle_rounded,
              title: '凉次元账号',
              description: '登录后可把收藏、观看记录与弹幕屏蔽词同步到自己的云端；只支持 QQ 邮箱注册，需要邮箱验证码。',
            ),
            _account.loggedIn ? _profileCard() : _authCard(),
            if (_message != null)
              SyncFeedback(message: _message!, error: _failed, busy: _busy),
          ],
        ),
      ),
    );
  }

  Widget _profileCard() {
    final profile = _account.profile!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              _Avatar(url: _account.avatarUrl, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.nickname.isEmpty ? '未设置昵称' : profile.nickname,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.email,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '修改昵称',
                onPressed: _busy ? null : _editNickname,
                icon: const Icon(Icons.edit_rounded),
              ),
            ],
          ),
        ),
        SettingsSection(
          margin: EdgeInsets.zero,
          tiles: [
            SettingsTile(
              leading: Icons.photo_camera_rounded,
              title: const Text('更换头像'),
              description: const Text('JPG / PNG / WebP，最大 2 MB'),
              trailing: const Icon(Icons.chevron_right_rounded),
              enabled: !_busy,
              onPressed: (_) => _pickAvatar(),
            ),
          ],
        ),
        SettingsSection(
          title: const Text('云同步'),
          margin: EdgeInsets.zero,
          tiles: [
            SettingsTile.switchTile(
              leading: Icons.collections_bookmark_rounded,
              title: const Text('同步收藏到账号'),
              description: const Text('在其他设备登录同一账号即可恢复收藏'),
              initialValue: GStorage.getSetting(SettingsKeys.accountSyncEnable),
              enabled: !_busy,
              onToggle: (value) async {
                // 点整行时 value 为 null，需按当前值取反而不是强制关闭。
                final next = value ??
                    !GStorage.getSetting(SettingsKeys.accountSyncEnable);
                await GStorage.putSetting(SettingsKeys.accountSyncEnable, next);
                if (mounted) setState(() {});
                if (next) await _syncNow();
              },
            ),
            SettingsTile.switchTile(
              leading: Icons.history_rounded,
              title: const Text('观看记录'),
              initialValue: GStorage.getSetting(
                SettingsKeys.webDavEnableHistory,
              ),
              enabled: !_busy,
              onToggle: (value) async {
                final next = value ??
                    !GStorage.getSetting(SettingsKeys.webDavEnableHistory);
                await GStorage.putSetting(SettingsKeys.webDavEnableHistory, next);
                if (mounted) setState(() {});
              },
            ),
            SettingsTile.switchTile(
              leading: Icons.collections_bookmark_rounded,
              title: const Text('收藏'),
              initialValue: GStorage.getSetting(
                SettingsKeys.webDavEnableCollect,
              ),
              enabled: !_busy,
              onToggle: (value) async {
                final next = value ??
                    !GStorage.getSetting(SettingsKeys.webDavEnableCollect);
                await GStorage.putSetting(SettingsKeys.webDavEnableCollect, next);
                if (mounted) setState(() {});
              },
            ),
            SettingsTile.switchTile(
              leading: Icons.shield_rounded,
              title: const Text('弹幕屏蔽词'),
              initialValue: GStorage.getSetting(
                SettingsKeys.webDavEnableDanmakuShield,
              ),
              enabled: !_busy,
              onToggle: (value) async {
                final next = value ??
                    !GStorage.getSetting(SettingsKeys.webDavEnableDanmakuShield);
                await GStorage.putSetting(
                  SettingsKeys.webDavEnableDanmakuShield,
                  next,
                );
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        SettingsSection(
          title: const Text('自动同步'),
          margin: EdgeInsets.zero,
          tiles: [
            SettingsDropdownTile<int>(
              leading: Icons.schedule_rounded,
              title: const Text('按时间自动同步'),
              description: Text(
                GStorage.getSetting(SettingsKeys.webDavAutoSyncMinutes) == 0
                    ? '仅在启动应用时同步一次'
                    : '后台${WebDavAutoSync.describeInterval(GStorage.getSetting(SettingsKeys.webDavAutoSyncMinutes))}自动同步',
              ),
              value: GStorage.getSetting(SettingsKeys.webDavAutoSyncMinutes),
              enabled: !_busy,
              options: {
                for (final minutes in WebDavAutoSync.intervalOptions)
                  minutes: WebDavAutoSync.describeInterval(minutes),
              },
              onChanged: (value) async {
                await GStorage.putSetting(
                  SettingsKeys.webDavAutoSyncMinutes,
                  value,
                );
                WebDavAutoSync().reschedule();
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        StateActionButton(
          onPressed: _busy ? null : _syncNow,
          text: _busy ? '请稍候…' : '立即同步全部数据',
          icon: Icons.sync_rounded,
        ),
        TextButton.icon(
          onPressed: _busy ? null : _logout,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('退出登录'),
        ),
      ],
    );
  }

  Widget _authCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'QQ 邮箱',
              hintText: '123456789@qq.com',
              border: OutlineInputBorder(),
            ),
          ),
          if (_registerMode) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '邮箱验证码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _busy || _cooldown > 0 ? null : _sendCode,
                  child: Text(_cooldown > 0 ? '${_cooldown}s 后重发' : '发送验证码'),
                ),
              ],
            ),
            TextField(
              controller: _nickname,
              maxLength: 24,
              decoration: const InputDecoration(
                labelText: '昵称（可选）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '密码',
              helperText: '至少 8 位',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscure ? '显示密码' : '隐藏密码',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
              ),
            ),
          ),
          StateActionButton(
            onPressed: _busy ? null : _submit,
            text: _busy ? '请稍候…' : (_registerMode ? '注册并登录' : '登录'),
            icon: Icons.login_rounded,
          ),
          TextButton(
            onPressed: _busy ? null : _showResetPasswordDialog,
            child: const Text('忘记密码？用邮箱验证码重置'),
          ),
          if (!_registerMode)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _registerMode = true;
                      _message = null;
                      _failed = false;
                    }),
              child: const Text('没有账号？注册'),
            )
          else
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _registerMode = false;
                      _message = null;
                      _failed = false;
                    }),
              child: const Text('已有账号？去登录'),
            ),
        ],
      ),
    );
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail,
  );
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();
  Timer? _timer;
  int _cooldown = 0;
  bool _busy = false;
  bool _failed = false;
  String _message = '验证码会发送到该邮箱（10 分钟内有效）';

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _emailValid => RegExp(
    r'^[\w.+-]+@(qq\.com|vip\.qq\.com|foxmail\.com)$',
    caseSensitive: false,
  ).hasMatch(_email.text.trim());

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown -= 1);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (!_emailValid) {
      setState(() {
        _failed = true;
        _message = '请填写 QQ 邮箱（@qq.com / @foxmail.com）';
      });
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
      _message = '正在发送验证码…';
    });
    try {
      await AccountService().sendCode(_email.text.trim(), purpose: 'reset');
      if (!mounted) return;
      _startCooldown();
      setState(() => _message = '验证码已发送，请查收 QQ 邮箱');
    } on AccountException catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = '操作失败：$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_emailValid) {
      setState(() {
        _failed = true;
        _message = '请填写 QQ 邮箱（@qq.com / @foxmail.com）';
      });
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() {
        _failed = true;
        _message = '请填写 6 位数字验证码';
      });
      return;
    }
    if (_password.text.length < 8) {
      setState(() {
        _failed = true;
        _message = '密码至少 8 位';
      });
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
      _message = '正在重置密码…';
    });
    try {
      await AccountService().resetPassword(
        email: _email.text.trim(),
        code: _code.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(_password.text);
    } on AccountException catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = '操作失败：$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('重置密码'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'QQ 邮箱',
                border: OutlineInputBorder(),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '验证码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _busy || _cooldown > 0 ? null : _sendCode,
                  child: Text(_cooldown > 0 ? '${_cooldown}s 后重发' : '发送验证码'),
                ),
              ],
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '新密码',
                helperText: '至少 8 位',
                border: OutlineInputBorder(),
              ),
            ),
            Text(
              _message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _failed
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('重置密码'),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, this.size = 40});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Icon(Icons.person_rounded, size: size);
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (context, _, _) => Icon(Icons.person_rounded, size: size),
      ),
    );
  }
}

/// 昵称编辑对话框：controller 由对话框自身持有并在 dispose 释放，
/// 避免页面在退场动画结束前就 dispose 掉仍在使用的 TextField。
class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.initial});

  final String initial;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改昵称'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 24,
        decoration: const InputDecoration(labelText: '昵称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
