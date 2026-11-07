import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_relation.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/services/account/account_service.dart';
import 'package:kazumi/services/account/rating_cache.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/modules/characters/character_item.dart';
import 'package:kazumi/modules/staff/staff_item.dart';

part 'info_controller.g.dart';

class InfoController = _InfoController with _$InfoController;

abstract class _InfoController with Store {
  _InfoController(this.collectController);

  final CollectController collectController;
  late BangumiItem bangumiItem;

  @observable
  bool isLoading = false;

  @observable
  var pluginSearchResponseList = ObservableList<PluginSearchResponse>();

  @observable
  var pluginSearchStatus = ObservableMap<String, PluginSearchStatus>();

  @observable
  var characterList = ObservableList<CharacterItem>();

  @observable
  var staffList = ObservableList<StaffFullItem>();

  @observable
  var relationList = ObservableList<BangumiRelation>();

  @observable
  bool relationsIsLoading = false;

  @observable
  bool relationsQueryTimeout = false;

  @observable
  bool relationsHasLoaded = false;

  /// 凉次元自建评分汇总；null 表示尚未加载完成。
  @observable
  AccountRating? rating;

  /// 读取本站评分（公开接口，带令牌时能拿到自己的分数）。
  @action
  Future<void> loadRating(int bangumiId) async {
    if (bangumiId <= 0) return;
    try {
      final account = AccountService()..ensureLoaded();
      final value = await AccountApi.instance.getRating(
        bangumiId,
        token: account.loggedIn ? account.token : null,
      );
      rating = value;
    } catch (e) {
      // 评分失败不影响页面其余内容；保持 null（卡片显示「暂无评分」）。
      KazumiLogger().w('InfoController: load rating failed', error: e);
      rating ??= AccountRating(
        bangumiId: bangumiId,
        count: 0,
        score: null,
        myScore: 0,
      );
    }
  }

  /// 提交评分并刷新汇总。
  @action
  Future<bool> submitRating(int bangumiId, int score) async {
    final account = AccountService()..ensureLoaded();
    if (!account.loggedIn) return false;
    try {
      rating = await AccountApi.instance.putRating(
        token: account.token,
        bangumiId: bangumiId,
        score: score,
      );
      // 同步写入列表缓存，返回列表时立刻能看到新评分。
      final updated = rating;
      if (updated != null) RatingCache().put(updated);
      return true;
    } on AccountException catch (e) {
      if (e.statusCode == 401) {
        await account.logout();
      }
      rethrow;
    }
  }

  int _relationRequestGeneration = 0;

  bool _isFillingInterestUserProfile = false;

  Future<bool> fillInterestUserProfileIfNeeded() async {
    final interest = bangumiItem.interest;
    if (interest == null || interest.hasUserProfile) {
      return false;
    }
    if (_isFillingInterestUserProfile) {
      return false;
    }
    _isFillingInterestUserProfile = true;
    try {
      final user = await BangumiApi.getCurrentUser();
      if (user == null) {
        return false;
      }
      bangumiItem.interest = interest.copyWithUser(user: user);
      await collectController.updateLocalCollect(bangumiItem);
      return true;
    } catch (e) {
      KazumiLogger().e(
        'InfoController: failed to fill interest user profile',
        error: e,
      );
      return false;
    } finally {
      _isFillingInterestUserProfile = false;
    }
  }

  Future<void> queryBangumiInfoByID(int id, {String type = "init"}) async {
    isLoading = true;
    try {
      await _updateBangumiInfoByID(id, type: type);
    } finally {
      isLoading = false;
    }
  }

  Future<void> refreshBangumiInfoByID(int id) async {
    await _updateBangumiInfoByID(id, type: "update");
  }

  Future<void> _updateBangumiInfoByID(int id, {required String type}) async {
    final value = await BangumiApi.getBangumiInfoByID(id);
    if (value == null) {
      return;
    }
    if (type == "init") {
      bangumiItem = value;
    } else {
      bangumiItem.summary = value.summary;
      bangumiItem.tags = value.tags;
      bangumiItem.rank = value.rank;
      bangumiItem.airDate = value.airDate;
      bangumiItem.airWeekday = value.airWeekday;
      bangumiItem.alias = value.alias;
      bangumiItem.ratingScore = value.ratingScore;
      bangumiItem.votes = value.votes;
      bangumiItem.votesCount = value.votesCount;
      final incomingInterest = value.interest;
      final previousInterest = bangumiItem.interest;
      if (incomingInterest == null) {
        bangumiItem.interest = null;
      } else if (previousInterest == null || !previousInterest.hasUserProfile) {
        bangumiItem.interest = incomingInterest;
      } else {
        bangumiItem.interest = incomingInterest.copyWithUser(
          user: previousInterest.user,
        );
      }
    }
    await collectController.updateLocalCollect(bangumiItem);
  }

  Future<void> queryBangumiCharactersByID(int id) async {
    characterList.clear();
    await BangumiApi.getCharatersByBangumiID(id).then((value) {
      characterList.addAll(value.charactersList);
    });
    Map<String, int> relationValue = {'主角': 1, '配角': 2, '客串': 3};

    try {
      characterList.sort((a, b) {
        int valueA = relationValue[a.relation] ?? 4;
        int valueB = relationValue[b.relation] ?? 4;
        return valueA.compareTo(valueB);
      });
    } catch (e) {
      KazumiDialog.showToast(message: '$e');
    }
    KazumiLogger().i(
      'InfoController: loaded character list length ${characterList.length}',
    );
  }

  Future<void> queryBangumiStaffsByID(int id) async {
    staffList.clear();
    await BangumiApi.getBangumiStaffByID(id).then((value) {
      staffList.addAll(value.data);
    });
    KazumiLogger().i(
      'InfoController: loaded staff list length ${staffList.length}',
    );
  }

  @action
  void clearRelations() {
    _relationRequestGeneration++;
    relationList = ObservableList<BangumiRelation>();
    relationsIsLoading = false;
    relationsQueryTimeout = false;
    relationsHasLoaded = false;
  }

  bool get canLoadRelations =>
      !relationsHasLoaded && !relationsIsLoading && !relationsQueryTimeout;

  @action
  Future<void> queryBangumiRelationsByID(int id) async {
    if (relationsIsLoading) return;

    final requestGeneration = ++_relationRequestGeneration;
    relationsIsLoading = true;
    relationsQueryTimeout = false;
    relationsHasLoaded = false;
    try {
      final relations = await resolveRelatedAnimeChain(
        currentSubjectId: id,
        fetchRelations: BangumiApi.getBangumiRelationsByID,
      );
      if (!_isCurrentRelationRequest(requestGeneration, id)) {
        return;
      }
      relationList = ObservableList<BangumiRelation>.of(relations);
      relationsHasLoaded = true;
      KazumiLogger().i(
        'InfoController: loaded related anime list length ${relationList.length}',
      );
    } catch (_) {
      if (_isCurrentRelationRequest(requestGeneration, id)) {
        relationsQueryTimeout = true;
        rethrow;
      }
    } finally {
      if (_isCurrentRelationRequest(requestGeneration, id)) {
        relationsIsLoading = false;
      }
    }
  }

  bool _isCurrentRelationRequest(int requestGeneration, int subjectId) =>
      requestGeneration == _relationRequestGeneration &&
      bangumiItem.id == subjectId;
}
