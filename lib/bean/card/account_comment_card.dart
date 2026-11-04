import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/bangumi_avatar.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/utils/date_time.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// 自建账号服务的评论卡片：条目吐槽、人物吐槽、单集讨论与用户主页共用。
/// 含剧透标记的内容默认折叠，点击展开。
class AccountCommentCard extends StatefulWidget {
  const AccountCommentCard(
    this.comment, {
    super.key,
    this.compact = false,
    this.onAvatarTap,
  });

  final AccountComment comment;
  final bool compact;

  /// 点击头像进入发布者主页；为空时不可点。
  final void Function(int userId)? onAvatarTap;

  @override
  State<AccountCommentCard> createState() => _AccountCommentCardState();
}

class _AccountCommentCardState extends State<AccountCommentCard> {
  bool _spoilerRevealed = false;

  @override
  void didUpdateWidget(covariant AccountCommentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换到另一条评论（列表复用）时重置剧透状态。
    if (oldWidget.comment.id != widget.comment.id) {
      _spoilerRevealed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final comment = widget.comment;
    final hidden = comment.spoiler && !_spoilerRevealed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(widget.compact ? 16 : 24),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.all(widget.compact ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Semantics(
                    button: true,
                    label: comment.nickname.isEmpty
                        ? '查看用户主页'
                        : '查看 ${comment.nickname} 的主页',
                    child: GestureDetector(
                      onTap: widget.onAvatarTap == null || comment.userId <= 0
                          ? null
                          : () => widget.onAvatarTap!(comment.userId),
                      child: BangumiAvatar(
                        radius: widget.compact ? 16 : 22,
                        imageUrl: comment.avatarUrl,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              comment.nickname.isEmpty
                                  ? '凉次元用户'
                                  : comment.nickname,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (comment.mine)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '我的',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.primaryContainer,
                                  ),
                                ),
                              ),
                            if (comment.spoiler)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.errorContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '剧透',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onErrorContainer,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dateFormat(comment.createdAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: widget.compact ? 10 : 16),
              if (hidden)
                Semantics(
                  button: true,
                  label: '展开剧透内容',
                  child: InkWell(
                    onTap: () => setState(() => _spoilerRevealed = true),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '该内容包含剧透，点击查看',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
              else
                SelectableText(
                  comment.content,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 把自建服务的 [AccountComment] 适配成单集讨论视图使用的
/// [EpisodeCommentItem]（该视图沿用既有排序逻辑）。
///
/// 剧透与「我的」标记无法通过 [EpisodeComment] 传递，单集讨论卡片
/// 渲染时会经过 [toAccountComment] 还原（见 [AccountCommentExtras]）。
class AccountCommentItem extends EpisodeCommentItem {
  AccountCommentItem.fromAccountComment(AccountComment comment)
    : _spoiler = comment.spoiler,
      _mine = comment.mine,
      super(
        comment: EpisodeComment(
          user: User(
            id: comment.userId,
            username: '',
            nickname: comment.nickname,
            avatar: UserAvatar(
              small: comment.avatarUrl,
              medium: comment.avatarUrl,
              large: comment.avatarUrl,
            ),
            sign: '',
            joinedAt: 0,
          ),
          comment: comment.content,
          createdAt: comment.createdAt,
        ),
        replies: const [],
      );

  /// 单集讨论视图无法从 EpisodeComment 取回的额外标记。
  final bool _spoiler;
  final bool _mine;
}

extension AccountCommentEpisodeComment on EpisodeCommentItem {
  /// 单集讨论卡片渲染回 [AccountComment]（还原剧透与「我的」标记）。
  AccountComment toAccountComment() {
    final item = this;
    return AccountComment(
      id: item.comment.user.id,
      content: item.comment.comment,
      spoiler: item is AccountCommentItem && item._spoiler,
      createdAt: item.comment.createdAt,
      userId: item.comment.user.id,
      nickname: item.comment.user.nickname,
      avatarUrl: item.comment.user.avatar.large,
      mine: item is AccountCommentItem && item._mine,
    );
  }
}

class AccountCommentCardBone extends StatelessWidget {
  const AccountCommentCardBone({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Skeletonizer.zone(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Bone.circle(size: 44),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Bone.text(width: 96),
                    SizedBox(height: 2),
                    Bone.text(width: 64, fontSize: 11),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Bone.multiText(lines: 2),
          ],
        ),
      ),
    );
  }
}