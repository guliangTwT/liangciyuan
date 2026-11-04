import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/bangumi_avatar.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/utils/date_time.dart';

/// 自建账号服务的评论卡片：条目吐槽、人物吐槽与单集讨论共用。
class AccountCommentCard extends StatelessWidget {
  const AccountCommentCard(this.comment, {super.key, this.compact = false});

  final AccountComment comment;
  final bool compact;

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
                    child: BangumiAvatar(
                      radius: compact ? 16 : 22,
                      imageUrl: comment.avatarUrl,
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
/// [EpisodeCommentItem]（该视图沿用既有卡片与排序逻辑）。
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
