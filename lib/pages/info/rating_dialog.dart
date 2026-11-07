import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

/// 评分对话框：1~10 分，滑动选择。
///
/// 返回选中的整数分数，取消时返回 null。只提交给凉次元自己的评分服务。
class RatingDialog extends StatefulWidget {
  const RatingDialog({
    super.key,
    required this.title,
    this.initialScore = 0,
  });

  /// 番剧标题，显示在对话框里让用户确认在给什么打分。
  final String title;

  /// 已有评分时预填；0 表示未评分。
  final int initialScore;

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  late double _score =
      widget.initialScore > 0 ? widget.initialScore.toDouble() : 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final hasScore = _score > 0;
    return AlertDialog(
      title: const Text('打个分'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                Text(
                  hasScore ? '${_score.round()} 分' : '点击星星打分',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: hasScore ? colors.primary : colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                RatingBar(
                  initialRating: _score / 2,
                  minRating: 0,
                  maxRating: 5,
                  allowHalfRating: false,
                  itemCount: 5,
                  itemSize: 40,
                  ratingWidget: RatingWidget(
                    full: Icon(Icons.star_rounded, color: colors.primary),
                    half: Icon(Icons.star_rounded, color: colors.primary),
                    empty: Icon(
                      Icons.star_outline_rounded,
                      color: colors.outline,
                    ),
                  ),
                  onRatingUpdate: (value) {
                    // 5 星映射成 10 分制，与卡片显示保持一致。
                    setState(() => _score = (value * 2).roundToDouble());
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '1 分 = 很差，10 分 = 极好',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
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
          onPressed: hasScore
              ? () => Navigator.of(context).pop(_score.round())
              : null,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
