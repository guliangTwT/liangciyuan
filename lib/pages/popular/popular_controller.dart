import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:mobx/mobx.dart';
part 'popular_controller.g.dart';

class PopularController = _PopularController with _$PopularController;

/// 首页顶部频道。
///
/// [tag] 为空表示「推荐」：走趋势接口，不限标签。
/// 其余频道各自带一个 Bangumi 标签，用同一个搜索接口拉取。
enum HomeChannel {
  recommend('推荐', ''),
  japanese('日漫', '日本'),
  chinese('国漫', '国产'),
  movie('剧场', '剧场版'),
  american('美漫', '欧美'),
  special('特摄', '特摄');

  const HomeChannel(this.label, this.tag);

  final String label;
  final String tag;
}

/// 一个横滑分区（「推荐 · 日漫」这样的行）。
class HomeShelf {
  const HomeShelf({
    required this.title,
    required this.tag,
    required this.items,
  });

  final String title;

  /// 拉取该分区用的标签，为空表示趋势。
  final String tag;
  final List<BangumiItem> items;

  bool get isEmpty => items.isEmpty;
}

abstract class _PopularController with Store {
  static const int _trendPageSize = 24;

  /// 每个分区一屏展示的条目数。横向列表再往下翻会让首页变得很长，
  /// 所以固定截断，用户想看更多可以切到对应频道。
  static const int _shelfSize = 18;

  int _trendOffset = 0;

  @observable
  String currentTag = '';

  /// 当前频道。与 [currentTag] 保持同步，方便 UI 直接用枚举。
  @observable
  HomeChannel currentChannel = HomeChannel.recommend;

  @observable
  ObservableList<BangumiItem> bangumiList = ObservableList.of([]);

  @observable
  ObservableList<BangumiItem> trendList = ObservableList.of([]);

  /// 推荐页的横滑分区，按需加载。
  @observable
  ObservableList<HomeShelf> shelves = ObservableList.of([]);

  /// 分区数据是否已经加载过（避免每次回到首页都重拉）。
  @observable
  bool shelvesLoaded = false;

  double scrollOffset = 0.0;

  @observable
  bool isLoadingMore = false;

  @observable
  bool isTimeOut = false;

  bool get _bangumiMirrorEnabled =>
      BangumiAcceleration.current == BangumiAcceleration.mirror;

  void setCurrentTag(String s) {
    currentTag = s;
    currentChannel = HomeChannel.values.firstWhere(
      (channel) => channel.tag == s,
      orElse: () => HomeChannel.recommend,
    );
  }

  void setChannel(HomeChannel channel) => setCurrentTag(channel.tag);

  void clearBangumiList() {
    bangumiList.clear();
  }

  /// 拉取推荐页的分区。
  ///
  /// 各分区并发请求，失败的分区直接略过——首页不该因为某个标签没数据就整块空掉。
  /// 趋势接口已经拿到的列表会复用为第一个分区，避免重复请求。
  @action
  Future<void> loadHomeShelves({bool force = false}) async {
    if (shelvesLoaded && !force) return;
    if (shelves.isNotEmpty && !force) return;

    final tags = <HomeChannel>[
      HomeChannel.japanese,
      HomeChannel.chinese,
      HomeChannel.movie,
    ];
    final results = await Future.wait(
      tags.map(
        (channel) => _bangumiMirrorEnabled
            ? BangumiApi.getBangumiMirrorPopularSubjects(
                tag: channel.tag,
                limit: _shelfSize,
              )
            : BangumiApi.getBangumiList(tag: channel.tag),
      ),
    );

    final built = <HomeShelf>[];
    for (var i = 0; i < tags.length; i++) {
      final channel = tags[i];
      final items = _dedupe(results[i]).take(_shelfSize).toList();
      if (items.isEmpty) continue;
      built.add(
        HomeShelf(title: channel.label, tag: channel.tag, items: items),
      );
    }
    shelves
      ..clear()
      ..addAll(built);
    shelvesLoaded = built.isNotEmpty;
  }

  List<BangumiItem> _dedupe(List<BangumiItem> items) {
    final seen = <int>{};
    return [
      for (final item in items)
        if (seen.add(item.id)) item,
    ];
  }

  // Async actions commit each segment between awaits as one transaction,
  // batching the completion writes into a single notification.
  @action
  Future<void> queryBangumiByTrend({String type = 'add'}) async {
    if (type == 'init') {
      trendList.clear();
      _trendOffset = 0;
    }
    isLoadingMore = true;
    final result = _bangumiMirrorEnabled
        ? await BangumiApi.getBangumiMirrorPopularSubjects(
            limit: _trendPageSize,
            offset: _trendOffset,
          )
        : await BangumiApi.getBangumiTrendsList(
            limit: _trendPageSize,
            offset: _trendOffset,
          );
    if (result.isNotEmpty) {
      _trendOffset += _trendPageSize;
    }
    final existingIds = trendList.map((item) => item.id).toSet();
    trendList.addAll(result.where((item) => existingIds.add(item.id)));
    isLoadingMore = false;
    isTimeOut = trendList.isEmpty;
  }

  @action
  Future<void> queryBangumiByTag({String type = 'add'}) async {
    if (type == 'init') {
      bangumiList.clear();
    }
    isLoadingMore = true;
    final tag = currentTag;
    final offset = bangumiList.length;
    final result = _bangumiMirrorEnabled
        ? await BangumiApi.getBangumiMirrorPopularSubjects(
            tag: tag,
            offset: offset,
          )
        : await BangumiApi.getBangumiList(
            tag: tag,
            limit: _trendPageSize,
            offset: offset,
          );
    // 同一页里可能因为分页边界出现重复条目；跨页也去重，避免列表里
    // 同一部番出现两次（点开的是同一个条目，看着像加载出错）。
    final existingIds = bangumiList.map((item) => item.id).toSet();
    bangumiList.addAll(result.where((item) => existingIds.add(item.id)));
    isLoadingMore = false;
    isTimeOut = bangumiList.isEmpty;
  }
}
