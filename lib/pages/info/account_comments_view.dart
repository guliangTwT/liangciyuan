import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/bangumi_avatar.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/services/account/account_service.dart';
import 'package:kazumi/utils/date_time.dart';

/// 条目「吐槽」页：读写在凉次元自有账号服务，不再依赖 Bangumi。
class AccountCommentsView extends StatefulWidget {
  const AccountCommentsView({
    super.key,
    required this.bangumiId,
    this.targetType = 'bangumi',
  });

  final int bangumiId;
  final String targetType;

  @override
  State<AccountCommentsView> createState() => _AccountCommentsViewState();
}

class _AccountCommentsViewState extends State<AccountCommentsView> {
  static const _pageSize = 20;

  final _scrollController = ScrollController();
  final _api = AccountApi.instance;

  final List<AccountComment> _items = [];
  final Set<int> _revealed = {};
  int _total = 0;
  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;

  String get _token => AccountService().token;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _load({required bool reset}) async {
    if (_loading) return;
    if (!reset && _items.length >= _total && _loaded) return;
    setState(() {
      _loading = true;
      if (reset) _failed = false;
    });
    try {
      final page = await _api.listComments(
        targetType: widget.targetType,
        targetId: widget.bangumiId,
        offset: reset ? 0 : _items.length,
        limit: _pageSize,
        token: _token.isEmpty ? null : _token,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        final known = _items.map((item) => item.id).toSet();
        _items.addAll(page.items.where((item) => !known.contains(item.id)));
        _total = page.total;
        _loaded = true;
        _failed = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
      });
      KazumiDialog.showToast(message: _describe(e));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_loaded || _items.length >= _total) return;
    await _load(reset: false);
  }

  String _describe(Object error) {
    if (error is AccountException) return error.message;
    return '吐槽加载失败，请稍后重试';
  }

  Future<void> _compose() async {
    if (_token.isEmpty) {
      KazumiDialog.showToast(message: '发表吐槽需要先登录凉次元账号');
      context.pushNamed('/settings/account');
      return;
    }
    final draft = await showModalBottomSheet<_Draft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: const _Composer(),
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await _api.createComment(
        token: _token,
        targetType: widget.targetType,
        targetId: widget.bangumiId,
        content: draft.content,
        spoiler: draft.spoiler,
      );
      if (!mounted) return;
      KazumiDialog.showToast(message: '吐槽已发布');
      await _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      KazumiDialog.showToast(message: _describe(e));
    }
  }

  Future<void> _delete(AccountComment comment) async {
    final confirmed = await KazumiDialog.show<bool>(
      builder: (context) => AlertDialog(
        title: const Text('删除这条吐槽？'),
        content: Text(comment.content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.deleteComment(token: _token, id: comment.id);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((item) => item.id == comment.id);
        _total = (_total - 1).clamp(0, 1 << 30);
      });
    } catch (e) {
      if (!mounted) return;
      KazumiDialog.showToast(message: _describe(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 950),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: _items.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) return _writeEntry(colors);
            if (index == _items.length + 1) return _footer(colors);
            final comment = _items[index - 1];
            return _commentCard(comment, colors);
          },
        ),
      ),
    );
  }

  Widget _writeEntry(ColorScheme colors) {
    final loggedIn = _token.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextButton(
        onPressed: _compose,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.all(16),
          backgroundColor: colors.surfaceContainerLow,
          foregroundColor: colors.onSurfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          children: [
            Icon(
              loggedIn ? Icons.edit_rounded : Icons.lock_outline_rounded,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                loggedIn ? '下面我简单喵两句' : '登录后即可发表吐槽',
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _footer(ColorScheme colors) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_failed && _items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Text('吐槽加载失败', style: TextStyle(color: colors.error)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _load(reset: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            '还没有人吐槽，来抢第一条',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }
    final hasMore = _items.length < _total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: hasMore
            ? TextButton(
                onPressed: _loadMore,
                child: Text('加载更多（$_total 条）'),
              )
            : Text(
                '共 $_total 条吐槽',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
      ),
    );
  }

  Widget _commentCard(AccountComment comment, ColorScheme colors) {
    final revealed = _revealed.contains(comment.id);
    final hidden = comment.spoiler && !revealed;
    return Card.filled(
      margin: const EdgeInsets.only(bottom: 8),
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BangumiAvatar(imageUrl: comment.avatarUrl),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            comment.nickname.isEmpty
                                ? '凉次元用户'
                                : comment.nickname,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (comment.mine)
                            _chip('我的吐槽', colors.primary, colors.primaryContainer),
                          if (comment.spoiler)
                            _chip('含剧透', colors.error, colors.errorContainer),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateFormat(comment.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (comment.mine)
                  IconButton(
                    tooltip: '删除',
                    onPressed: () => _delete(comment),
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (hidden)
              InkWell(
                onTap: () => setState(() => _revealed.add(comment.id)),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '这条吐槽含剧透，点击查看',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              )
            else
              SelectableText(comment.content),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: foreground),
      ),
    );
  }
}

class _Draft {
  const _Draft({required this.content, required this.spoiler});

  final String content;
  final bool spoiler;
}

class _Composer extends StatefulWidget {
  const _Composer();

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _controller = TextEditingController();
  bool _spoiler = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final content = _controller.text.trim();
    if (content.isEmpty) {
      KazumiDialog.showToast(message: '先写点什么再发布吧');
      return;
    }
    Navigator.of(context).pop(_Draft(content: content, spoiler: _spoiler));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '发表吐槽',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: '说说这部番……',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _spoiler,
            onChanged: (value) => setState(() => _spoiler = value),
            title: const Text('含剧透（默认折叠内容）'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('发布'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}