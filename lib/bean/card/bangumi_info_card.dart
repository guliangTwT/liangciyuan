import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:kazumi/bean/widget/collect_button.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:skeletonizer/skeletonizer.dart';

// 视频卡片 - 水平布局
class BangumiInfoCardV extends StatefulWidget {
  const BangumiInfoCardV({
    super.key,
    required this.bangumiItem,
    required this.isLoading,
    required this.showRating,
    this.rating,
    this.onRate,
  });

  final BangumiItem bangumiItem;
  final bool isLoading;
  final bool showRating;

  /// 凉次元自建评分汇总；null 表示尚未加载。
  final AccountRating? rating;

  /// 打开评分面板；null 表示不可评分（未登录）。
  final VoidCallback? onRate;

  @override
  State<BangumiInfoCardV> createState() => _BangumiInfoCardVState();
}

class _BangumiInfoCardVState extends State<BangumiInfoCardV> {
  int touchedIndex = -1;

  /// 评分行：只展示凉次元自己的评分。
  ///
  /// - 没有评分时显示「暂无评分」，不再回落到 Bangumi/第三方的分数。
  /// - 有评分时显示「N 人评分」+ 平均分 + 星级，并支持登录后打分。
  Widget _buildRatingRow(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rating = widget.rating;
    final hasScore = rating?.hasScore ?? false;
    final count = rating?.count ?? 0;
    final score = rating?.score ?? 0;
    final canRate = widget.onRate != null;

    final Widget scoreArea = hasScore
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 8),
              RatingBarIndicator(
                itemCount: 5,
                // 10 分制换算成 5 颗星。
                rating: (score / 2).clamp(0.0, 5.0),
                itemBuilder: (context, index) => Icon(
                  Icons.star_rounded,
                  color: colors.primary,
                ),
                itemSize: 20.0,
              ),
            ],
          )
        : Text(
            '暂无评分',
            style: TextStyle(
              fontSize: 14,
              color: colors.onSurfaceVariant,
            ),
          );

    final Widget summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(hasScore ? '$count 人评分:' : '凉次元评分:'),
        const SizedBox(height: 2),
        scoreArea,
      ],
    );

    if (!canRate) return summary;
    return InkWell(
      onTap: widget.onRate,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: summary),
            const SizedBox(width: 10),
            // 未评分时强调可以打分；已评分时显示自己的分数。
            Text(
              rating?.rated == true ? '我的 ${rating!.myScore} 分' : '去评分',
              style: TextStyle(
                fontSize: 12,
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      constraints: BoxConstraints(maxWidth: 950),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.bangumiItem.nameCn == ''
                ? widget.bangumiItem.name
                : (widget.bangumiItem.nameCn),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: AspectRatio(
                    aspectRatio: 0.65,
                    child: LayoutBuilder(builder: (context, boxConstraints) {
                      final double maxWidth = boxConstraints.maxWidth;
                      final double maxHeight = boxConstraints.maxHeight;
                      return Hero(
                        transitionOnUserGestures: true,
                        flightShuttleBuilder:
                            NetworkImgLayer.heroFlightShuttleBuilder,
                        tag: widget.bangumiItem.id,
                        child: NetworkImgLayer(
                          src: widget.bangumiItem.images['large'] ?? '',
                          width: maxWidth,
                          height: maxHeight,
                          fadeInDuration: const Duration(milliseconds: 0),
                          fadeOutDuration: const Duration(milliseconds: 0),
                        ),
                      );
                    }),
                  ),
                ),
                SizedBox(width: 16),
                Flexible(
                  child: Skeletonizer(
                    enabled: widget.isLoading,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Shrink under large system font so the collect button
                        // stays inside the fixed-height card.
                        Flexible(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.only(bottom: 8),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '放送开始:',
                                  ),
                                  Text(
                                    widget.bangumiItem.airDate == ''
                                        ? '2000-11-11' // Skeleton Loader 占位符
                                        : widget.bangumiItem.airDate,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  if (widget.isLoading)
                                    // Skeleton Loader 占位符
                                    Text(
                                      '10.0 ********',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    )
                                  else if (widget.showRating)
                                    _buildRatingRow(context),
                                  SizedBox(height: 8),
                                  Text(
                                    'Bangumi Ranked:',
                                  ),
                                  Text(
                                    widget.showRating
                                        ? '#${widget.bangumiItem.rank}'
                                        : '***',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          height: 40,
                          child: CollectButton.extend(
                            bangumiItem: widget.bangumiItem,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 评分透视（各分数段人数分布）已移除：那是 Bangumi 的
                // 第三方统计，本站评分只展示平均分与人数。
              ],
            ),
          ),
        ],
      ),
    );
  }
}
