// ignore_for_file: library_private_types_in_public_api

import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/services/account/account_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/utils/danmaku.dart';

part 'player_danmaku_controller.g.dart';

class PlayerDanmakuController = _PlayerDanmakuController
    with _$PlayerDanmakuController;

enum DanmakuLoadStatus {
  success,
  empty,
  failed,
}

class DanmakuLoadResult {
  const DanmakuLoadResult({
    required this.danmakus,
    required this.bangumiID,
    required this.status,
  });

  factory DanmakuLoadResult.success({
    required List<DanmakuEntry> danmakus,
    required int bangumiID,
  }) {
    return DanmakuLoadResult(
      danmakus: danmakus,
      bangumiID: bangumiID,
      status: danmakus.isEmpty
          ? DanmakuLoadStatus.empty
          : DanmakuLoadStatus.success,
    );
  }

  factory DanmakuLoadResult.failed({
    required int bangumiID,
  }) {
    return DanmakuLoadResult(
      danmakus: const [],
      bangumiID: bangumiID,
      status: DanmakuLoadStatus.failed,
    );
  }

  final List<DanmakuEntry> danmakus;
  final int bangumiID;
  final DanmakuLoadStatus status;

  bool get hasDanmakus => status == DanmakuLoadStatus.success;

  bool get isFailed => status == DanmakuLoadStatus.failed;
}

class DanmakuTimeline {
  static int? resolveSourceSecond(
    Duration playbackPosition,
    double timelineOffsetSeconds,
  ) {
    final sourceMilliseconds = playbackPosition.inMilliseconds -
        (timelineOffsetSeconds * 1000).round();
    if (sourceMilliseconds < 0) {
      return null;
    }
    return Duration(milliseconds: sourceMilliseconds).inSeconds;
  }

  static int staggerDelayMilliseconds({
    required int index,
    required int total,
  }) {
    if (total <= 0) {
      return 0;
    }
    return index * 1000 ~/ total;
  }
}

abstract class _PlayerDanmakuController with Store {
  _PlayerDanmakuController({
    required this.isLocalPlayback,
    required this.downloadController,
    required this.currentBangumiId,
    required this.currentEpisodeNumber,
  });

  final bool Function() isLocalPlayback;
  final DownloadController downloadController;

  /// 发送弹幕时用来定位 (番剧, 集数) 的上下文。
  final int Function() currentBangumiId;
  final int Function() currentEpisodeNumber;

  late canvas.DanmakuController canvasController;
  bool _canvasAttached = false;

  /// 由播放器画布创建回调调用，房间弹幕在画布就绪前到达时会被丢弃。
  void attachCanvasController(canvas.DanmakuController controller) {
    canvasController = controller;
    _canvasAttached = true;
  }

  bool get roomDanmakuEnabled =>
      GStorage.getSetting(SettingsKeys.danmakuRoomEnabled);

  bool get roomDanmakuOnly =>
      GStorage.getSetting(SettingsKeys.danmakuRoomOnly);

  /// 一起看房间消息以弹幕形式展示，房间内所有人都能看到。
  ///
  /// [local] 为本人刚发送的消息，即使关闭了房间弹幕显示也会回显。
  void showRoomDanmaku({
    required String username,
    required String message,
    bool local = false,
  }) {
    if (!_canvasAttached) {
      return;
    }
    if (!local && !roomDanmakuEnabled) {
      return;
    }
    final text = message.trim();
    if (text.isEmpty) {
      return;
    }
    final name = username.trim();
    canvasController.addDanmaku(
      DanmakuContentItem(
        name.isEmpty ? text : '$name：$text',
        color: Colors.orange,
        isColorful: true,
        type: _visibleRoomDanmakuType(),
        extra: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// 房间弹幕不应受「顶部/滚动/底部」显示开关影响而被整类隐藏，
  /// 因此选用当前画布上可见的类型，优先底部。
  DanmakuItemType _visibleRoomDanmakuType() {
    final option = canvasController.option;
    if (!option.hideBottom) {
      return DanmakuItemType.bottom;
    }
    if (!option.hideScroll) {
      return DanmakuItemType.scroll;
    }
    if (!option.hideTop) {
      return DanmakuItemType.top;
    }
    return DanmakuItemType.scroll;
  }

  Future<void> setRoomDanmakuEnabled(bool value) {
    return GStorage.putSetting<bool>(SettingsKeys.danmakuRoomEnabled, value);
  }

  /// 开启「只看房间弹幕」时清掉画布上已经排队的普通弹幕。
  Future<void> setRoomDanmakuOnly(bool value) {
    if (value && _canvasAttached) {
      canvasController.clear();
    }
    return GStorage.putSetting<bool>(SettingsKeys.danmakuRoomOnly, value);
  }

  final Map<int, List<DanmakuEntry>> danDanmakus = {};
  @observable
  bool danmakuOn = false;
  @observable
  bool danmakuLoading = false;

  int bangumiID = 0;
  int _scheduledDanmakuGeneration = 0;

  int get scheduledDanmakuGeneration => _scheduledDanmakuGeneration;

  double get timelineOffsetSeconds {
    final offset = GStorage.getSetting(SettingsKeys.danmakuTimeOffset);
    return offset;
  }

  int? resolveDanmakuSecond(Duration playbackPosition) {
    return DanmakuTimeline.resolveSourceSecond(
      playbackPosition,
      timelineOffsetSeconds,
    );
  }

  List<DanmakuEntry> danmakusForPlaybackPosition(Duration playbackPosition) {
    final danmakuSecond = resolveDanmakuSecond(playbackPosition);
    if (danmakuSecond == null) {
      return const [];
    }
    return danDanmakus[danmakuSecond] ?? const [];
  }

  @action
  void setDanmakuEnabled(bool value) {
    danmakuOn = value;
  }

  void clearAndInvalidateScheduledDanmakus() {
    _scheduledDanmakuGeneration++;
    canvasController.clear();
  }

  // Apply fetched data only after VideoPageController validates the session.
  Future<DanmakuLoadResult> fetchDanmaku(
    int bangumiId,
    String pluginName,
    int episode,
  ) async {
    if (isLocalPlayback()) {
      return await _fetchCachedDanmaku(
        bangumiId,
        pluginName,
        episode,
      );
    }
    return await _fetchDanDanmakuByBgmBangumiID(
      bangumiId,
      episode,
    );
  }

  @action
  void beginDanmakuLoad() {
    danDanmakus.clear();
    danmakuLoading = true;
  }

  @action
  void applyDanmakuLoad(
    DanmakuLoadResult result, {
    required bool enableDanmaku,
  }) {
    bangumiID = result.bangumiID;
    addDanmakus(result.danmakus);
    danmakuOn = enableDanmaku;
    danmakuLoading = false;
  }

  @action
  void applyUnavailableDanmakuLoad(DanmakuLoadResult result) {
    bangumiID = result.bangumiID;
    danDanmakus.clear();
    danmakuOn = false;
    danmakuLoading = false;
  }

  @action
  void finishDanmakuLoad({bool disableDanmaku = false}) {
    if (disableDanmaku) {
      danDanmakus.clear();
      danmakuOn = false;
    }
    danmakuLoading = false;
  }

  Future<DanmakuLoadResult> _fetchCachedDanmaku(
      int bangumiId, String pluginName, int episode) async {
    KazumiLogger().i(
        'PlayerController: attempting to load cached danmaku for episode $episode');
    var nextBangumiID = bangumiId;
    try {
      final cachedDanmakus = await downloadController.getCachedDanmakus(
        bangumiId,
        pluginName,
        episode,
      );

      if (cachedDanmakus != null && cachedDanmakus.isNotEmpty) {
        KazumiLogger().i(
            'PlayerController: loaded ${cachedDanmakus.length} cached danmakus');
        return DanmakuLoadResult.success(
          danmakus: cachedDanmakus,
          bangumiID: nextBangumiID,
        );
      } else {
        KazumiLogger()
            .i('PlayerController: no cached danmaku, attempting online fetch');
        try {
          // 本地缓存缺失时改从自建服务拉取，不再解析第三方 ID。
          nextBangumiID = bangumiId;
          final page = await AccountApi.instance.listDanmaku(
            bangumiId: bangumiId,
            episode: episode,
          );
          final res = [for (final item in page.items) item.toDanmakuEntry()];
          if (res.isNotEmpty) {
            KazumiLogger()
                .i('PlayerController: fetched ${res.length} danmakus online');
            _saveDanmakuToCache(downloadController, bangumiId, pluginName,
                episode, res, nextBangumiID);
          }
          return DanmakuLoadResult.success(
            danmakus: res,
            bangumiID: nextBangumiID,
          );
        } catch (e) {
          KazumiLogger().w(
              'PlayerController: failed to fetch danmaku online (may be offline)',
              error: e);
          return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
        }
      }
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: failed to load cached danmaku', error: e);
      return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
    }
  }

  void _saveDanmakuToCache(
      DownloadController downloadController,
      int bangumiId,
      String pluginName,
      int episode,
      List<DanmakuEntry> danmakus,
      int danDanID) {
    try {
      downloadController.updateCachedDanmakus(
        bangumiId,
        pluginName,
        episode,
        danmakus,
        danDanID,
      );
      KazumiLogger()
          .i('PlayerController: saved ${danmakus.length} danmakus to cache');
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: failed to save danmaku to cache', error: e);
    }
  }

  Future<DanmakuLoadResult> _fetchDanDanmakuByBgmBangumiID(
      int bgmBangumiID, int episode) async {
    KazumiLogger().i(
        'PlayerController: loading danmaku from account service '
        '[Bangumi $bgmBangumiID ep$episode]');
    try {
      final page = await AccountApi.instance.listDanmaku(
        bangumiId: bgmBangumiID,
        episode: episode,
      );
      return DanmakuLoadResult.success(
        danmakus: [for (final item in page.items) item.toDanmakuEntry()],
        bangumiID: bgmBangumiID,
      );
    } catch (e) {
      KazumiLogger().w(
          'PlayerController: failed to load account danmaku $bgmBangumiID/$episode',
          error: e);
      return DanmakuLoadResult.failed(bangumiID: bgmBangumiID);
    }
  }

  /// 把弹幕发到凉次元自有弹幕库；失败时提示但保留本地回显。
  Future<bool> sendDanmaku({
    required String content,
    required Duration position,
  }) async {
    final account = AccountService()..ensureLoaded();
    if (!account.loggedIn) {
      KazumiDialog.showToast(message: '发送弹幕需要先登录凉次元账号');
      return false;
    }
    final bangumiId = currentBangumiId();
    final episode = currentEpisodeNumber();
    if (bangumiId <= 0) {
      KazumiDialog.showToast(message: '当前剧集无法发送弹幕');
      return false;
    }
    try {
      await AccountApi.instance.postDanmaku(
        token: account.token,
        bangumiId: bangumiId,
        episode: episode,
        positionMs: position.inMilliseconds,
        content: content,
      );
      // 合并进本地时间轴，进度条/重播时无需再拉一次。
      final entry = DanmakuEntry(
        message: content,
        time: position.inMilliseconds / 1000,
        type: 1,
        color: const Color(0xFFFFFFFF),
        source: 'liangciyuan',
      );
      (danDanmakus[entry.time.toInt()] ??= <DanmakuEntry>[]).add(entry);
      return true;
    } on AccountException catch (e) {
      if (e.statusCode == 401) {
        await account.logout();
        KazumiDialog.showToast(message: '登录状态已过期，请重新登录');
      } else {
        KazumiDialog.showToast(message: e.message);
      }
    } catch (e) {
      KazumiLogger().w('Danmaku: send failed', error: e);
      KazumiDialog.showToast(message: '弹幕发送失败，请稍后重试');
    }
    return false;
  }

  void addDanmakus(List<DanmakuEntry> danmakus) {
    final bool danmakuDeduplicationEnable =
        GStorage.getSetting(SettingsKeys.danmakuDeduplication);

    final List<DanmakuEntry> listToAdd = danmakuDeduplicationEnable
        ? mergeDuplicateDanmakus(danmakus, timeWindowSeconds: 5)
        : danmakus;

    for (final element in listToAdd) {
      final danmakuSecond = element.time.toInt();
      (danDanmakus[danmakuSecond] ??= <DanmakuEntry>[]).add(element);
    }
  }

  void updateDanmakuSpeed(double playerSpeed) {
    final baseDuration = GStorage.getSetting(SettingsKeys.danmakuDuration);
    final followSpeed = GStorage.getSetting(SettingsKeys.danmakuFollowSpeed);

    final duration = followSpeed ? (baseDuration / playerSpeed) : baseDuration;
    canvasController
        .updateOption(canvasController.option.copyWith(duration: duration));
  }
}
