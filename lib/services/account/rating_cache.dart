import 'dart:async';

import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/services/account/account_service.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 评分缓存：列表页只需一次批量请求就能拿到整屏条目的评分。
///
/// 设计取舍：
/// - **按需批量**：调用方给出当前要显示的 id，服务把未缓存的合并成一次请求。
/// - **短 TTL**：评分变化不频繁，缓存 5 分钟足以避免滚动时反复请求；
///   自己打分后会主动写入缓存，立刻保持一致。
/// - **失败静默**：拿不到评分时不影响列表显示，卡片会显示「暂无评分」。
class RatingCache {
  RatingCache._();

  static final RatingCache _instance = RatingCache._();

  factory RatingCache() => _instance;

  static const Duration _ttl = Duration(minutes: 5);

  final Map<int, AccountRating> _ratings = {};
  final Map<int, DateTime> _fetchedAt = {};
  final Map<int, double> _bangumiScoreFallback = {};

  /// 已缓存的评分；没有则返回 null（调用方据此决定显示什么）。
  AccountRating? ratingOf(int bangumiId) {
    final cached = _ratings[bangumiId];
    if (cached == null) return null;
    final at = _fetchedAt[bangumiId];
    if (at != null && DateTime.now().difference(at) > _ttl) {
      return cached; // 过期也先显示旧值，随后由 prefetch 刷新。
    }
    return cached;
  }

  /// 列表里显示的分数：优先本站评分，没有评分时显示「暂无评分」。
  ///
  /// 注意这里**不再回落到 [fallback]（Bangumi 分数）**：产品要求只用自己的
  /// 数据。参数保留是为了让调用点明确表达「不再使用第三方分数」。
  String displayScoreFor(int bangumiId) {
    final rating = ratingOf(bangumiId);
    if (rating == null) return '暂无评分';
    return rating.displayScore;
  }

  bool shouldShowStars(int bangumiId) => ratingOf(bangumiId)?.hasScore ?? false;

  double starsFor(int bangumiId) {
    final score = ratingOf(bangumiId)?.score ?? 0;
    return (score / 2).clamp(0.0, 5.0);
  }

  /// 为一批条目补齐评分（只请求未缓存或已过期的）。
  ///
  /// 返回 true 表示缓存确实有更新，调用方据此决定是否重建 UI；
  /// 全部命中缓存时不会触发多余的重建。
  Future<bool> prefetch(Iterable<int> bangumiIds) async {
    final now = DateTime.now();
    final missing = <int>[];
    for (final id in bangumiIds) {
      if (id <= 0) continue;
      final at = _fetchedAt[id];
      if (at != null && now.difference(at) <= _ttl) continue;
      if (!missing.contains(id)) missing.add(id);
    }
    if (missing.isEmpty) return false;
    try {
      final account = AccountService()..ensureLoaded();
      final fetched = await AccountApi.instance.getRatings(
        missing,
        token: account.loggedIn ? account.token : null,
      );
      for (final entry in fetched.entries) {
        _ratings[entry.key] = entry.value;
        _fetchedAt[entry.key] = now;
      }
      // 请求成功但服务端没有该条目：缓存一个空评分，避免反复请求。
      for (final id in missing) {
        if (!_ratings.containsKey(id)) {
          _ratings[id] = AccountRating(
            bangumiId: id,
            count: 0,
            score: null,
            myScore: 0,
          );
          _fetchedAt[id] = now;
        }
      }
      return true;
    } catch (e) {
      KazumiLogger().w('RatingCache: prefetch failed', error: e);
      return false;
    }
  }

  /// 自己打分后写入缓存，列表立刻更新。
  void put(AccountRating rating) {
    _ratings[rating.bangumiId] = rating;
    _fetchedAt[rating.bangumiId] = DateTime.now();
  }

  void clear() {
    _ratings.clear();
    _fetchedAt.clear();
    _bangumiScoreFallback.clear();
  }
}
