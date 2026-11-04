import 'dart:async';

import 'package:kazumi/services/account/account_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/danmaku_shield_sync_service.dart';
import 'package:kazumi/services/sync/webdav.dart';

/// 按设定间隔在后台自动执行账号云同步。
///
/// 间隔来自 [SettingsKeys.webDavAutoSyncMinutes]（分钟，0 表示关闭）。
/// 只在账号云同步已启用、且至少开启了一项同步内容时才会真正同步；
/// 所有同步都自带串行队列与去重，重复触发是安全的。
class WebDavAutoSync {
  WebDavAutoSync._();

  static final WebDavAutoSync _instance = WebDavAutoSync._();

  /// 应用级共享实例；依赖通过 [configure] 注入。
  factory WebDavAutoSync() => _instance;

  DanmakuShieldSyncService? _danmakuShieldSync;
  WebDav? _webDav;

  Timer? _timer;
  bool _running = false;

  /// 注入依赖。重复调用以最后一次为准，便于测试替换。
  void configure({
    required DanmakuShieldSyncService danmakuShieldSync,
    required WebDav webDav,
  }) {
    _danmakuShieldSync = danmakuShieldSync;
    _webDav = webDav;
  }

  static const List<int> intervalOptions = [0, 15, 30, 60, 180];

  static String describeInterval(int minutes) => switch (minutes) {
    0 => '仅启动时同步',
    _ when minutes % 60 == 0 => '每 ${minutes ~/ 60} 小时',
    _ => '每 $minutes 分钟',
  };

  /// 根据当前设置（重新）安排定时器。
  void reschedule() {
    _timer?.cancel();
    _timer = null;

    final minutes = GStorage.getSetting(SettingsKeys.webDavAutoSyncMinutes);
    if (minutes <= 0) {
      KazumiLogger().i('WebDav: auto sync disabled');
      return;
    }
    if (!GStorage.getSetting(SettingsKeys.accountSyncEnable) ||
        !(AccountService()..ensureLoaded()).loggedIn) {
      KazumiLogger().i('CloudSync: auto sync skipped, account not ready');
      return;
    }

    final interval = Duration(minutes: minutes);
    _timer = Timer.periodic(interval, (_) => unawaited(syncNow()));
    KazumiLogger().i(
      'WebDav: auto sync scheduled every ${interval.inMinutes} minutes',
    );
  }

  /// 立即执行一次自动同步（定时器与手动触发共用）。
  Future<void> syncNow() async {
    if (_running) return;
    if (!GStorage.getSetting(SettingsKeys.accountSyncEnable) ||
        !(AccountService()..ensureLoaded()).loggedIn) {
      return;
    }

    final enableHistory = GStorage.getSetting(SettingsKeys.webDavEnableHistory);
    final enableCollect = GStorage.getSetting(SettingsKeys.webDavEnableCollect);
    final enableShield = GStorage.getSetting(
      SettingsKeys.webDavEnableDanmakuShield,
    );
    if (!enableHistory && !enableCollect && !enableShield) return;

    final webDav = _webDav ?? WebDav();
    _running = true;
    try {
      if (!webDav.initialized) await webDav.init();

      if (enableShield) {
        final shieldSync = _danmakuShieldSync;
        if (shieldSync != null) {
          await shieldSync.syncIfEnabled();
        } else {
          KazumiLogger().w(
            'WebDav: auto sync skipped danmaku shield, service not injected',
          );
        }
      }
      if (enableHistory) {
        await webDav.syncHistory();
      }
      if (enableCollect) {
        await webDav.syncCollectibles();
      }
      KazumiLogger().i('WebDav: auto sync completed');
    } catch (e, stackTrace) {
      KazumiLogger().w(
        'WebDav: auto sync failed',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
