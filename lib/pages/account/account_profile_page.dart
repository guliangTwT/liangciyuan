import 'package:flutter/material.dart';

import 'package:kazumi/bean/card/account_comment_card.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/author_title_badge.dart';
import 'package:kazumi/bean/widget/bangumi_avatar.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/modules/my/watch_stats.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/services/account/account_service.dart';
import 'package:kazumi/utils/date_time.dart';

/// 抖音式头部：大头像 + 昵称 + 加入时间，下方统计行。
class ProfileHeaderView extends StatelessWidget {
  const ProfileHeaderView({
    super.key,
    required this.avatarUrl,
    required this.nickname,
    required this.joinedAt,
    required this.subtitle,
    this.title = '',
    this.onAvatarTap,
  });

  final String avatarUrl;
  final String nickname;
  final int? joinedAt;
  final String subtitle;

  /// 服务端授予的称号；空字符串表示没有。
  final String title;
  final VoidCallback? onAvatarTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    final joinedText = joinedAt == null || joinedAt! <= 0
        ? null
        : '加入于 ${formatDateTime(DateTime.fromMillisecondsSinceEpoch(joinedAt! * 1000))}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                button: onAvatarTap != null,
                label: onAvatarTap != null ? '编辑资料或查看主页' : null,
                child: GestureDetector(
                  onTap: onAvatarTap,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [colors.primary, colors.tertiary],
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.surface,
                      ),
                      child: ClipOval(
                        child: SizedBox(
                          width: 88,
                          height: 88,
                          child: avatarUrl.isEmpty
                              ? Icon(
                                  Icons.person_rounded,
                                  size: 48,
                                  color: colors.onSurfaceVariant,
                                )
                              : BangumiAvatar(
                                  imageUrl: avatarUrl,
                                  radius: 44,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nickname.isEmpty ? '凉次元用户' : nickname,
                      style: theme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (title.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      AuthorTitleBadge(title: title, compact: false),
                    ],
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (joinedText != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        joinedText,
                        style: theme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 观看足迹头部卡片（个人主页用），点击进入历史记录页。
class ProfileStatsBar extends StatelessWidget {
  const ProfileStatsBar({
    super.key,
    required this.stats,
    required this.onOpenHistory,
  });

  final WatchStats stats;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Semantics(
        button: true,
        label: '查看观看足迹',
        child: Material(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpenHistory,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.sentiment_satisfied_alt_rounded,
                    color: colors.onPrimaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '观看足迹',
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _stat(
                    colors,
                    '${stats.watchedBangumiCount} 部番剧 · '
                    '${stats.watchedEpisodeCount} 集',
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onPrimaryContainer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 统计文案用弹性宽度 + 省略号：窄屏或大字号下不会顶出 Row。
  Widget _stat(ColorScheme colors, String text) {
    return Flexible(
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: TextStyle(color: colors.onPrimaryContainer),
      ),
    );
  }
}

/// 他人主页：展示公开资料与其发布的评论。
class AccountProfilePage extends StatefulWidget {
  const AccountProfilePage({super.key, required this.userId});

  final int userId;

  @override
  State<AccountProfilePage> createState() => _AccountProfilePageState();
}

class _AccountProfilePageState extends State<AccountProfilePage> {
  AccountUserProfile? _profile;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.userId <= 0) {
      // 路由参数非法（非数字或 0）时不发请求，直接显示错误态。
      _loading = false;
      _failed = true;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final profile = await AccountApi.instance.getUserProfile(
        widget.userId,
        token: AccountService().token,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profile = _profile;
    return SettingsDetailScaffold(
      title: Text(
        profile == null
            ? '用户主页'
            : (profile.nickname.isEmpty ? '凉次元用户' : profile.nickname),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? GeneralErrorWidget(
              title: '用户主页加载失败',
              errMsg: '请检查网络后重试。',
              onRetry: _load,
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                ProfileHeaderView(
                  avatarUrl: profile?.avatarUrl ?? '',
                  nickname: profile?.nickname ?? '',
                  title: profile?.title ?? '',
                  joinedAt: profile?.joinedAt,
                  subtitle: '${profile?.commentCount ?? 0} 条评论',
                ),
                const SizedBox(height: 8),
                if (profile == null || profile.comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        '还没有发布过评论',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  for (final comment in profile.comments)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: AccountCommentCard(comment),
                    ),
              ],
            ),
    );
  }
}

/// 「个人主页」标签页的头部数据（自己登录的账号）。
class ProfileHeaderData {
  const ProfileHeaderData({
    required this.avatarUrl,
    required this.nickname,
    required this.joinedAt,
    required this.subtitle,
    required this.isOwn,
    this.title = '',
  });

  final String avatarUrl;
  final String nickname;

  /// 账号用户 ID；未登录为 null。
  final int? joinedAt;
  final String subtitle;
  final bool isOwn;

  /// 服务端授予的称号；空字符串表示没有。
  final String title;
}
