import 'package:flutter/services.dart' show appBuildName;

class ApiEndpoints {
  /// 当前版本
  static const String version = appBuildName ?? '0.0.0';

  /// 规则API级别
  static const int apiLevel = 9;

  /// 项目主页（GitHub 是主发布渠道，Codeberg 为后备）
  static const String projectUrl = "https://github.com/guliangTwT/liangciyuan";

  /// 源码主页
  static const String sourceUrl = projectUrl;

  /// 后备镜像（GitHub 不可达时使用）
  static const String mirrorProjectUrl =
      "https://codeberg.org/GuLiang/liangciyuan";

  /// 发布页：没有应用内安装包时，用户在这里手动下载
  static const String releasePage = "$projectUrl/releases";

  /// 改编来源（Kazumi）
  static const String upstreamUrl = "https://github.com/Predidit/Kazumi";

  /// 图标作者
  static const String iconUrl = "https://www.pixiv.net/users/66219277";

  /// 规则仓库
  static const String pluginShop =
      'https://raw.githubusercontent.com/Predidit/KazumiRules/main/';

  /// 规则仓库镜像
  static const String ghProxyHost = 'gh-proxy.org';
  static const String ghProxyMirror = 'https://$ghProxyHost/';
  static const String ghfastMirror = 'https://ghfast.top/';
  static const String gitcodeMirror =
      'https://raw.gitcode.com/gh_mirrors/ka/KazumiRules/raw/main/';

  /// 在线升级：GitHub 为主源
  static const String latestApp =
      'https://api.github.com/repos/guliangTwT/liangciyuan/releases/latest';

  /// 在线升级：Codeberg 后备源（GitHub 拿不到时用）
  static const String latestAppFallback =
      'https://codeberg.org/api/v1/repos/GuLiang/liangciyuan/releases/latest';

  /// GitHub 发布页（主）
  static const String latestAppFallbackPage = "$mirrorProjectUrl/releases";

  /// Bangumi 镜像测试后端
  static const String bangumiMirrorDomain = 'https://api.kazumi.fyi';

  /// 凉次元 Release 镜像后端（上游镜像不提供本改编版安装包）
  static const String latestAppMirror = latestApp;

  /// 弹弹官网
  static const String dandanIndex = 'https://www.dandanplay.com/';

  /// Bangumi 官网
  static const String bangumiIndex = 'https://bangumi.tv/';

  /// bangumi API
  static const String bangumiAPIDomain = 'https://api.bgm.tv';

  /// Bangumi 鉴权 API
  static const String bangumiAuthAPIMirrorDomain = 'https://api.bgmapi.com';

  /// 上游 Kazumi 镜像后端
  static const String upstreamAppMirror =
      '$bangumiMirrorDomain/kazumi/v1/app/latest';

  /// 番剧信息
  static const String bangumiInfoByID = '/v0/subjects/{0}';

  /// 条目关联信息
  static const String bangumiRelationsByID = '/v0/subjects/{0}/subjects';

  /// 条目搜索
  static const String bangumiRankSearch =
      '/v0/search/subjects?limit={0}&offset={1}';

  /// 从条目ID获取角色信息
  static const String bangumiCharacterByID = '/v0/subjects/{0}/characters';

  /// 从条目ID获取工作人员信息
  static const String bangumiStaffByID = '/v0/subjects/{0}/persons';

  /// 从条目ID获取剧集ID
  static const String bangumiEpisodeByID = '/v0/episodes';

  /// 返回当前 Access Token 对应的用户信息
  static const String bangumiUsernameByToken = '/v0/me';

  /// 新增或修改用户单个条目收藏
  static const String bangumiSetCollection = '/v0/users/-/collections/{0}';

  /// 获取用户全部收藏（不限类型）。用户名，分页参数1(limit)，分页参数2(offset)
  static const String bangumiGetAllCollections =
      '/v0/users/{0}/collections?subject_type=2&limit={1}&offset={2}';

  /// Bangumi Next API Domain
  static const String bangumiAPINextDomain = 'https://next.bgm.tv';

  static const bangumiPublicApiHosts = {'api.bgm.tv', 'next.bgm.tv'};

  /// 每日放送
  static const String bangumiCalendar = '/p1/calendar';

  /// 番剧趋势
  static const String bangumiTrendsNext = '/p1/trending/subjects';

  /// Kazumi Bangumi 镜像缓存榜单
  static const String bangumiMirrorPopularSubjects =
      '/kazumi/v1/popular/subjects';

  /// Kazumi Bangumi 镜像季节时间表
  static const String bangumiMirrorSeasonCalendar =
      '/kazumi/v1/calendar/season';

  /// 番剧信息
  static const String bangumiInfoByIDNext = '/p1/subjects/{0}';

  /// 番剧角色信息
  static const String bangumiCharacterInfoByCharacterIDNext =
      '/p1/characters/{0}';

  /// DanDanPlay API Domain
  static const String dandanAPIDomain = 'https://api.dandanplay.net';

  /// 获取弹幕
  static const String dandanAPIComment = "/api/v2/comment/";

  /// 检索弹弹番剧元数据
  static const String dandanAPISearchEpisodes = "/api/v2/search/episodes";

  /// 获取弹弹番剧元数据
  static const String dandanAPIInfo = "/api/v2/bangumi/";

  /// 获取弹弹番剧元数据（通过BGM番剧ID）
  static const String dandanAPIInfoByBgmBangumiId = "/api/v2/bangumi/bgmtv/{0}";

  /// 图片识别番剧
  static const String traceApi = 'https://api.trace.moe/search';

  static String formatUrl(String url, List<dynamic> params) {
    for (int i = 0; i < params.length; i++) {
      url = url.replaceAll('{$i}', params[i].toString());
    }
    return url;
  }
}
