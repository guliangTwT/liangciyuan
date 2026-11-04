import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/bangumi_avatar.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/utils/date_time.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// 自建账号服务的评论卡片：条目吐槽、人物吐槽与单集讨论共用。
class AccountCommentCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(compact ? 16 : 24),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ExcludeSemantics(
                    child: GestureDetector(
                      onTap: onAvatarTap == null || comment.userId <= 0
                          ? null
                          : () => onAvatarTap!(comment.userId),
                      child: BangumiAvatar(
                        radius: compact ? 16 : 22,
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
              SizedBox(height: compact ? 10 : 16),
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
class AccountCommentItem extends EpisodeCommentItem {
  AccountCommentItem.fromAccountComment(AccountComment comment)
    : super(
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
}

extension AccountCommentEpisodeComment on EpisodeComment {
  /// 单集讨论卡片渲染回 [AccountComment]。
  AccountComment toAccountComment() {
    return AccountComment(
      id: user.id,
      content: comment,
      spoiler: false,
      createdAt: createdAt,
      userId: user.id,
      nickname: user.nickname,
      avatarUrl: user.avatar.large,
      mine: false,
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
