import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/history_sync_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 观看集数同步的回归测试。
///
/// 曾经的缺陷：`appendSafely` 判断的是已废弃的 `webDavEnable` 开关
/// （没有任何界面会写它），于是每次观看产生的进度事件都被静默丢弃——
/// 收藏能同步，但「看到第几集」永远同步不到新设备。
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('history_gate_test_');
    PathProviderPlatform.instance = _TestPaths(tempDir.path);
    Hive.init(tempDir.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    // 清理上一次测试写入的日志。
    final log = await HistorySyncService.forTesting(tempDir)
        .localChangeLogFile();
    if (await log.exists()) await log.delete();
    await GStorage.resetSettings([
      SettingsKeys.accountSyncEnable,
      SettingsKeys.webDavEnable,
      SettingsKeys.webDavEnableHistory,
    ]);
  });

  Future<String> readLog() async {
    final service = HistorySyncService.forTesting(tempDir);
    final file = await service.localChangeLogFile();
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  test('records watch progress when account sync is enabled', () async {
    await GStorage.putSetting(SettingsKeys.accountSyncEnable, true);
    await GStorage.putSetting(SettingsKeys.webDavEnableHistory, true);

    final service = HistorySyncService.forTesting(tempDir);
    await service.appendSafely(
      () => service.appendUpsertProgress(
        history: _history(episode: 75),
        episode: 75,
        road: 0,
        progressMs: 90 * 1000,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    final log = await readLog();
    expect(log, isNotEmpty, reason: '观看进度必须写入本地事件日志');
    expect(log, contains('upsertWatchState'));
  });

  test('stays silent when history sync is turned off', () async {
    await GStorage.putSetting(SettingsKeys.accountSyncEnable, true);
    await GStorage.putSetting(SettingsKeys.webDavEnableHistory, false);

    final service = HistorySyncService.forTesting(tempDir);
    await service.appendSafely(
      () => service.appendUpsertProgress(
        history: _history(episode: 3),
        episode: 3,
        road: 0,
        progressMs: 1000,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    expect(await readLog(), isEmpty);
  });

  test('stays silent when account sync is turned off', () async {
    await GStorage.putSetting(SettingsKeys.accountSyncEnable, false);
    await GStorage.putSetting(SettingsKeys.webDavEnableHistory, true);

    final service = HistorySyncService.forTesting(tempDir);
    await service.appendSafely(
      () => service.appendUpsertProgress(
        history: _history(episode: 4),
        episode: 4,
        road: 0,
        progressMs: 1000,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    expect(await readLog(), isEmpty);
  });
}

History _history({required int episode}) {
  return History(
    _item(),
    episode,
    'plugin',
    DateTime.fromMillisecondsSinceEpoch(1700000000000),
    'https://example.com/video',
    'EP$episode',
  );
}

BangumiItem _item() {
  return BangumiItem(
    id: 1,
    type: 2,
    name: 'subject 1',
    nameCn: '条目 1',
    summary: '',
    airDate: '2026-01-01',
    airWeekday: 4,
    rank: 0,
    images: const {
      'large': '',
      'common': '',
      'medium': '',
      'small': '',
      'grid': '',
    },
    tags: const <BangumiTag>[],
    alias: const [],
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}
