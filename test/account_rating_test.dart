import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/services/account/rating_cache.dart';

/// 评分展示规则：只用凉次元自己的数据，没有评分就显示「暂无评分」。
void main() {
  group('AccountRating', () {
    test('has no score when nobody rated', () {
      final rating = AccountRating.fromJson({
        'bangumiId': 500000,
        'count': 0,
        'score': null,
        'myScore': 0,
      });

      expect(rating.hasScore, isFalse);
      expect(rating.displayScore, '暂无评分');
      expect(rating.rated, isFalse);
    });

    test('shows one decimal when rated', () {
      final rating = AccountRating.fromJson({
        'bangumiId': 500000,
        'count': 3,
        'score': 8.25,
        'myScore': 9,
      });

      expect(rating.hasScore, isTrue);
      // 服务端已四舍五入到一位，这里只保证格式正确。
      expect(rating.displayScore, '8.3');
      expect(rating.rated, isTrue);
      expect(rating.myScore, 9);
    });

    test('treats a missing score field as unrated', () {
      final rating = AccountRating.fromJson({'bangumiId': 1, 'count': 5});

      expect(rating.hasScore, isFalse);
      expect(rating.displayScore, '暂无评分');
    });
  });

  group('RatingCache', () {
    setUp(() => RatingCache().clear());

    test('unrated items display 暂无评分 instead of a third-party score', () {
      // 关键回归：不能回落到 Bangumi 的 ratingScore。
      expect(RatingCache().displayScoreFor(999999), '暂无评分');
      expect(RatingCache().shouldShowStars(999999), isFalse);
      expect(RatingCache().starsFor(999999), 0);
    });

    test('put() makes the score visible immediately', () {
      RatingCache().put(
        const AccountRating(
          bangumiId: 42,
          count: 2,
          score: 7.0,
          myScore: 7,
        ),
      );

      expect(RatingCache().displayScoreFor(42), '7.0');
      expect(RatingCache().shouldShowStars(42), isTrue);
      // 10 分制换算成 5 星。
      expect(RatingCache().starsFor(42), closeTo(3.5, 0.001));
    });

    test('clear() drops every cached score', () {
      RatingCache().put(
        const AccountRating(
          bangumiId: 7,
          count: 1,
          score: 5.0,
          myScore: 5,
        ),
      );
      RatingCache().clear();

      expect(RatingCache().displayScoreFor(7), '暂无评分');
    });

    test('prefetch with an empty list is a no-op', () async {
      expect(await RatingCache().prefetch(const []), isFalse);
      expect(RatingCache().displayScoreFor(1), '暂无评分');
    });

    test('prefetch returns false when everything is already cached', () async {
      RatingCache().put(
        const AccountRating(
          bangumiId: 11,
          count: 1,
          score: 6.0,
          myScore: 6,
        ),
      );
      // 已缓存且未过期：不应触发请求，也不该让调用方重建 UI。
      expect(await RatingCache().prefetch(const [11]), isFalse);
    });
  });
}