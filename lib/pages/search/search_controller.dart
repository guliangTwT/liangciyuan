import 'dart:io';

import 'package:mobx/mobx.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/search/image_search_module.dart';
import 'package:kazumi/modules/search/search_history_module.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/apis/trace_api.dart';
import 'package:kazumi/utils/search_parser.dart';

part 'search_controller.g.dart';

class SearchPageController = _SearchPageController with _$SearchPageController;

abstract class _SearchPageController with Store {
  static const int _searchPageSize = 20;
  static const int _maxPagesPerSearch = 3;

  _SearchPageController(
    this._collectRepository,
    this._searchHistoryRepository,
  );

  final ICollectRepository _collectRepository;
  final ISearchHistoryRepository _searchHistoryRepository;

  int _searchOffset = 0;
  int _searchGeneration = 0;

  bool hasMoreSearchResults = true;

  @observable
  bool isLoading = false;

  @observable
  bool isTimeOut = false;

  @observable
  bool notShowWatchedBangumis = false;

  @observable
  bool notShowAbandonedBangumis = false;

  @observable
  ObservableList<BangumiItem> bangumiList = ObservableList.of([]);

  @observable
  ObservableList<SearchHistory> searchHistories = ObservableList.of([]);

  @observable
  bool isImageSearching = false;

  /// 上一次搜索是否因网络/接口失败（区别于「确实没有结果」）。
  ///
  /// 以前两者都表现成「没有找到番剧」，断网时用户会以为片名不存在，
  /// 也没有重试入口。
  @observable
  bool searchFailed = false;

  @observable
  String imageSearchError = '';

  @observable
  ObservableList<ResultItem> imageSearchResults = ObservableList.of([]);

  @action
  void loadSearchHistories() {
    final histories = _searchHistoryRepository.getAllHistories();
    searchHistories.clear();
    searchHistories.addAll(histories);
  }

  @action
  Future<void> searchBangumi(String input, {String type = 'add'}) async {
    if (type == 'add' && (isLoading || !hasMoreSearchResults)) return;
    final generation = type == 'add' ? _searchGeneration : ++_searchGeneration;
    isLoading = true;
    isTimeOut = false;
    searchFailed = false;
    if (type != 'add') {
      bangumiList.clear();
      _searchOffset = 0;
      hasMoreSearchResults = true;
      if (!_collectRepository.getPrivateMode() && input.trim().isNotEmpty) {
        await _searchHistoryRepository.deleteDuplicates(input);
        if (_searchHistoryRepository.isHistoryFull(10)) {
          await _searchHistoryRepository.deleteOldest();
        }
        await _searchHistoryRepository.saveHistory(input);
        loadSearchHistories();
      }
    }
    if (generation != _searchGeneration) return;
    final filterState = SearchParser(input).toFilterState();
    final id = int.tryParse(filterState.id);
    if (id != null) {
      final item = await BangumiApi.getBangumiInfoByID(id);
      if (generation != _searchGeneration) return;
      if (item != null) {
        bangumiList.add(item);
      }
      hasMoreSearchResults = false;
      isLoading = false;
      isTimeOut = bangumiList.isEmpty;
      return;
    }
    var pagesFetched = 0;
    do {
      final page = await BangumiApi.bangumiSearch(filterState.keyword,
          tags: filterState.tags,
          limit: _searchPageSize,
          offset: _searchOffset,
          sort: filterState.sort,
          dateRange: filterState.effectiveDateRange,
          rankRange: filterState.rankRange,
          scoreRange: filterState.scoreRange,
          weekdays: filterState.weekdays);
      // Discard stale responses before mutating the current search.
      if (generation != _searchGeneration) return;
      if (page == null) {
        // 请求失败：与「零结果」区分开，界面显示错误态并提供重试。
        if (bangumiList.isEmpty) searchFailed = true;
        break;
      }
      pagesFetched++;
      _searchOffset += page.rawCount;
      hasMoreSearchResults = page.rawCount == _searchPageSize;
      final existingIds = bangumiList.map((item) => item.id).toSet();
      final newItems =
          page.items.where((item) => existingIds.add(item.id)).toList();
      if (newItems.isNotEmpty) {
        bangumiList.addAll(newItems);
        break;
      }
    } while (hasMoreSearchResults && pagesFetched < _maxPagesPerSearch);
    isLoading = false;
    isTimeOut =
        bangumiList.isEmpty && (pagesFetched == 0 || !hasMoreSearchResults);
    if (searchFailed) isTimeOut = false;
  }

  @action
  Future<void> deleteSearchHistory(SearchHistory history) async {
    await _searchHistoryRepository.deleteHistory(history);
    loadSearchHistories();
  }

  @action
  Future<void> clearSearchHistory() async {
    await _searchHistoryRepository.clearAllHistories();
    loadSearchHistories();
  }

  @action
  void clearImageSearchState() {
    isImageSearching = false;
    imageSearchError = '';
    imageSearchResults.clear();
  }

  @action
  Future<void> searchImageByFile(File imageFile) async {
    isImageSearching = true;
    imageSearchError = '';
    imageSearchResults.clear();
    try {
      final result = await TraceApi.searchAnimeByImageFile(imageFile);
      imageSearchResults.addAll(result.result ?? []);
      if (result.error != null && result.error!.isNotEmpty) {
        imageSearchError = result.error!;
      } else if (imageSearchResults.isEmpty) {
        imageSearchError = '未找到匹配结果';
      }
    } catch (e) {
      imageSearchError = '图片搜索失败，请稍后重试';
    } finally {
      isImageSearching = false;
    }
  }

  @action
  Future<void> searchImageByUrl(String imageUrl) async {
    isImageSearching = true;
    imageSearchError = '';
    imageSearchResults.clear();
    try {
      final result = await TraceApi.searchAnimeByImageUrl(imageUrl);
      imageSearchResults.addAll(result.result ?? []);
      if (result.error != null && result.error!.isNotEmpty) {
        imageSearchError = result.error!;
      } else if (imageSearchResults.isEmpty) {
        imageSearchError = '未找到匹配结果';
      }
    } catch (e) {
      imageSearchError = '图片搜索失败，请检查图片地址或稍后重试';
    } finally {
      isImageSearching = false;
    }
  }

  @action
  Future<void> setNotShowWatchedBangumis(bool value) async {
    notShowWatchedBangumis = value;
    invalidateHiddenBangumiIds();
  }

  @action
  Future<void> setNotShowAbandonedBangumis(bool value) async {
    notShowAbandonedBangumis = value;
    invalidateHiddenBangumiIds();
  }

  Set<int> loadWatchedBangumiIds() {
    return _collectRepository.getBangumiIdsByType(CollectType.watched);
  }

  Set<int> loadAbandonedBangumiIds() {
    return _collectRepository.getBangumiIdsByType(CollectType.abandoned);
  }

  /// 需要从结果里过滤掉的番剧 ID（已看过 + 已抛弃）。
  ///
  /// 搜索页的 build 里要用它来过滤结果，而 build 可能因任何状态变化重跑
  /// （输入、滚动、加载态…）。以前每次都调用上面两个方法，等于**每次 build
  /// 都遍历两遍整张收藏表**。这里按开关组合缓存一份。
  ///
  /// 缓存加了短有效期：收藏表没有变更通知可订阅（`CollectRepository` 只有
  /// 直接读写），用户在别处改完收藏再回到搜索页时，最多 [hiddenIdsTtl]
  /// 之后就会重新读一次，不会长期显示过时的过滤结果。
  static const hiddenIdsTtl = Duration(seconds: 3);

  Set<int>? _hiddenIdsCache;
  (bool, bool)? _hiddenIdsCacheKey;
  DateTime? _hiddenIdsCachedAt;

  Set<int> hiddenBangumiIds() {
    final watched = notShowWatchedBangumis;
    final abandoned = notShowAbandonedBangumis;
    if (!watched && !abandoned) return const <int>{};

    final key = (watched, abandoned);
    final cached = _hiddenIdsCache;
    final cachedAt = _hiddenIdsCachedAt;
    if (cached != null &&
        _hiddenIdsCacheKey == key &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < hiddenIdsTtl) {
      return cached;
    }

    // 两个开关都要时只扫一遍表。
    final types = <CollectType>[
      if (watched) CollectType.watched,
      if (abandoned) CollectType.abandoned,
    ];
    final result = types.length == 1
        ? _collectRepository.getBangumiIdsByType(types.single)
        : _collectRepository.getBangumiIdsByTypes(types);
    _hiddenIdsCache = result;
    _hiddenIdsCacheKey = key;
    _hiddenIdsCachedAt = DateTime.now();
    return result;
  }

  /// 明确知道收藏变了（例如设置页改完开关）时立即作废旧结果。
  void invalidateHiddenBangumiIds() {
    _hiddenIdsCache = null;
    _hiddenIdsCacheKey = null;
    _hiddenIdsCachedAt = null;
  }
}
