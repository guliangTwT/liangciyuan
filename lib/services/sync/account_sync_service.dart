import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/services/account/account_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/danmaku_shield_sync_service.dart';
import 'package:kazumi/services/sync/webdav.dart';

/// 同步中每一步的进度回调。
typedef SyncStepCallback =
    void Function(String message, {required int step, required int total});

/// 一次「全部数据」同步的结果。
///
/// 各步骤互相独立：一项失败不影响其余项，也不会把失败伪装成成功。
class FullSyncResult {
  const FullSyncResult({required this.succeeded, required this.failures});

  /// 成功执行的步骤名。
  final List<String> succeeded;

  /// 失败信息（「步骤名：原因」）。
  final List<String> failures;

  bool get hasFailure => failures.isNotEmpty;
  bool get didAnything => succeeded.isNotEmpty || failures.isNotEmpty;

  /// 面向用户的一句话总结。
  String get message {
    if (!didAnything) return '没有开启任何同步内容';
    if (!hasFailure) {
      return succeeded.isEmpty ? '已经是最新' : '已同步：${succeeded.join('、')}';
    }
    if (succeeded.isEmpty) return '同步失败\n${failures.join('\n')}';
    return '部分同步完成（${succeeded.join('、')}）\n${failures.join('\n')}';
  }
}

/// 从任意入口发起「收藏 + 观看记录 + 弹幕屏蔽词」的完整同步。
///
/// 账号页与追番页共用同一实现，避免两处行为不一致（历史上只有账号页
/// 能同步全部内容，追番页只能同步收藏）。
class AccountSyncService {
  AccountSyncService._();

  static final AccountSyncService _instance = AccountSyncService._();

  factory AccountSyncService() => _instance;

  /// 当前设置下是否至少开启了一项同步内容。
  static bool get hasContentEnabled =>
      GStorage.getSetting(SettingsKeys.webDavEnableHistory) ||
      GStorage.getSetting(SettingsKeys.webDavEnableCollect) ||
      GStorage.getSetting(SettingsKeys.webDavEnableDanmakuShield);

  /// 登录 + 总开关 + 至少一项内容，全部就绪才可同步。
  static bool get canSync {
    final account = AccountService()..ensureLoaded();
    return account.loggedIn &&
        GStorage.getSetting(SettingsKeys.accountSyncEnable) &&
        hasContentEnabled;
  }

  /// 执行同步。
  ///
  /// [onStep] 用于进度提示；[reloadCollectibles] 在收藏同步后刷新列表。
  Future<FullSyncResult> syncAll({
    SyncStepCallback? onStep,
    void Function()? reloadCollectibles,
    bool includeCollect = true,
    bool includeHistory = true,
    bool includeShield = true,
  }) async {
    final account = AccountService()..ensureLoaded();
    if (!account.loggedIn) {
      return const FullSyncResult(
        succeeded: [],
        failures: ['登录状态已失效，请重新登录'],
      );
    }
    if (!GStorage.getSetting(SettingsKeys.accountSyncEnable)) {
      return const FullSyncResult(
        succeeded: [],
        failures: ['未开启账号云同步'],
      );
    }

    final enableHistory =
        includeHistory && GStorage.getSetting(SettingsKeys.webDavEnableHistory);
    final enableCollect =
        includeCollect && GStorage.getSetting(SettingsKeys.webDavEnableCollect);
    final enableShield = includeShield &&
        GStorage.getSetting(SettingsKeys.webDavEnableDanmakuShield);
    final total =
        [enableHistory, enableCollect, enableShield].where((v) => v).length;
    if (total == 0) {
      return const FullSyncResult(succeeded: [], failures: []);
    }

    final succeeded = <String>[];
    final failures = <String>[];
    final sync = WebDav();
    var step = 0;

    void reportStep(String message) {
      step++;
      onStep?.call(message, step: step, total: total);
    }

    try {
      await sync.ensureReady();
    } catch (e) {
      KazumiLogger().w('AccountSync: connect failed', error: e);
      return FullSyncResult(
        succeeded: const [],
        failures: ['连接同步服务：${WebDav.describeError(e)}'],
      );
    }

    if (enableShield) {
      reportStep('正在同步弹幕屏蔽词…');
      try {
        // 用 sync() 而不是 syncIfEnabled()：后者会吞掉异常，
        // 失败会被静默掩盖（用户只会看到「同步完成」）。
        await inject<DanmakuShieldSyncService>().sync();
        succeeded.add('弹幕屏蔽词');
      } catch (e) {
        KazumiLogger().w('AccountSync: danmaku shield failed', error: e);
        failures.add('弹幕屏蔽词：${WebDav.describeError(e)}');
      }
    }
    if (enableHistory) {
      reportStep('正在同步观看记录…');
      try {
        await sync.syncHistory();
        succeeded.add('观看记录');
      } catch (e) {
        KazumiLogger().w('AccountSync: history failed', error: e);
        failures.add('观看记录：${WebDav.describeError(e)}');
      }
    }
    if (enableCollect) {
      reportStep('正在同步收藏…');
      try {
        await sync.syncCollectibles();
        succeeded.add('收藏');
        reloadCollectibles?.call();
      } catch (e) {
        KazumiLogger().w('AccountSync: collect failed', error: e);
        failures.add('收藏：${WebDav.describeError(e)}');
      }
    }

    return FullSyncResult(succeeded: succeeded, failures: failures);
  }
}
