import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/comment_composer_sheet.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/author_title_badge.dart';
import 'package:kazumi/bean/widget/bangumi_avatar.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/services/account/account_service.dart';
import 'package:kazumi/utils/comment_pagination.dart';
import 'package:kazumi/utils/date_time.dart';

/// 条目「评论」页：读写在凉次元自有账号服务，不再依赖 Bangumi。
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

  final _api = AccountApi.instance;

  final List<AccountComment> _items = [];
  final Set<int> _revealed = {};
  int _total = 0;
  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;
  DateTime? _lastLoadMoreAt;

  /// 下一页的偏移量。不能用 `_items.length`：列表已按 id 去重，
  /// 一旦服务端返回的页里有重复条目，长度就不再增长，偏移会卡死，
  /// 用户点「加载更多」也永远看不到后面的内容。
  int _offset = 0;

  String get _token => AccountService().token;

  @override
  void initState() {
    super.initState();
    // 登录/退出后（从账号页返回）需要刷新发布入口的状态。
    AccountService().addListener(_onAccountChanged);
    _load(reset: true);
  }

  void _onAccountChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AccountService().removeListener(_onAccountChanged);
    super.dispose();
  }

  /// 滚动通知是高频的；失败后 3 秒冷却，避免连续失败的重试风暴。
  void _maybeLoadMore() {
    if (_loading || !_loaded || _offset >= _total) return;
    final last = _lastLoadMoreAt;
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(seconds: 3)) {
      return;
    }
    _lastLoadMoreAt = now;
    _loadMore();
  }

  Future<void> _load({required bool reset}) async {
    if (_loading) return;
    if (!reset && _loaded && _offset >= _total) return;
    setState(() {
      _loading = true;
      if (reset) _failed = false;
    });
    final requestOffset = reset ? 0 : _offset;
    try {
      final page = await _api.listComments(
        targetType: widget.targetType,
        targetId: widget.bangumiId,
        offset: requestOffset,
        limit: _pageSize,
        token: _token.isEmpty ? null : _token,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items.clear();
          _offset = 0;
        }
        final known = _items.map((item) => item.id).toSet();
        _items.addAll(page.items.where((item) => !known.contains(item.id)));
        // 偏移按服务端返回的条数推进，与服务端分页保持一致；
        // 空页时把偏移推到总数，避免无限重试同一条空页。
        _offset = CommentPagination.nextOffset(
          currentOffset: requestOffset,
          receivedItems: page.items.length,
          total: page.total,
        );
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
    if (_loading || !_loaded || _offset >= _total) return;
    await _load(reset: false);
  }

  String _describe(Object error) {
    if (error is AccountException) return error.message;
    return '评论加载失败，请稍后重试';
  }

  Future<void> _compose() async {
    if (_token.isEmpty) {
      KazumiDialog.showToast(message: '发表评论需要先登录凉次元账号');
      context.pushNamed('/settings/account');
      return;
    }
    final draft = await showCommentComposerSheet(
      context,
      title: '发表评论',
      hintText: '说说这部番……',
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
      KazumiDialog.showToast(message: '评论已发布');
      await _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      if (e is AccountException && e.statusCode == 401) {
        // 令牌失效：清掉本地登录态，入口回到「登录后可发表」。
        await AccountService().logout();
      }
      if (!mounted) return;
      KazumiDialog.showToast(message: _describe(e));
    }
  }

  Future<void> _delete(AccountComment comment) async {
    final confirmed = await KazumiDialog.show<bool>(
      builder: (context) => AlertDialog(
        title: const Text('删除这条评论？'),
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
      if (e is AccountException && e.statusCode == 401) {
        await AccountService().logout();
      }
      if (!mounted) return;
      KazumiDialog.showToast(message: _describe(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // 与其它 Tab 一致：CustomScrollView + SliverOverlapInjector，
    // 否则列表会钻到 pinned 的 SliverAppBar 底下，也无法收起头部。
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // 贴近底部时加载下一页；ScrollController 交给 NestedScrollView，
        // 显式 controller 会打断它和头部折叠的联动。
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 240) {
          _maybeLoadMore();
        }
        return false;
      },
      child: CustomScrollView(
        key: const PageStorageKey<String>('account-comments'),
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(child: _writeEntry(colors)),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) =>
                  _commentCard(_items[index], colors),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverToBoxAdapter(child: _footer(colors)),
          ),
        ],
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
                loggedIn ? '下面我简单喵两句' : '登录后即可发表评论',
                overflow: TextOverflow.ellipsis,
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
              Text('评论加载失败', style: TextStyle(color: colors.error)),
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
            '还没有人评论，来抢第一条',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }
    // 以服务端分页进度判断是否还有更多；列表长度可能因去重而小于偏移。
    final hasMore = CommentPagination.hasMore(offset: _offset, total: _total);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: hasMore
            ? TextButton(
                onPressed: _loadMore,
                child: Text('加载更多（$_total 条）'),
              )
            : Text(
                '共 $_total 条评论',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
      ),
    );
  }

  Widget _commentCard(AccountComment comment, ColorScheme colors) {
    final revealed = _revealed.contains(comment.id);
    final hidden = comment.spoiler && !revealed;
    // 有称号的用户（凉次元作者）：只加一条左侧竖线做标记，
    // 与单集讨论卡片保持一致；正文样式不特殊化。
    final authored = comment.title.isNotEmpty;
    return Card.filled(
      margin: const EdgeInsets.only(bottom: 8),
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: authored
            ? const BorderSide(color: Color(0xFFD9A020), width: 0)
            : BorderSide.none,
      ),
      child: Container(
        decoration: authored
            ? const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFFD9A020), width: 3),
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: comment.userId <= 0
                        ? null
                        : () => context.pushNamed(
                            '/settings/profile/${comment.userId}',
                          ),
                    child: BangumiAvatar(imageUrl: comment.avatarUrl),
                  ),
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
                          if (comment.title.isNotEmpty)
                            AuthorTitleBadge(title: comment.title),
                          if (comment.mine)
                            _chip('我的评论', colors.primary, colors.primaryContainer),
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
                    '这条评论含剧透，点击查看',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              )
            else
              SelectableText(comment.content),
          ],
            ),
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