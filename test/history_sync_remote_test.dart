import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/webdav.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

/// 「看到第几集」跨设备同步的端到端回归测试。
///
/// 曾经的缺陷：进度事件因判断了废弃开关而不再写入日志，且快照只在首次
/// 同步时发布一次，于是新设备登录后只能拿到收藏，集数永远对不上。
void main() {
  late Directory tempDir;
  late _MemoryClient client;
  final webDav = WebDav();
  const historyKey = 'plugin1::online';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('history_remote_test_');
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

  Future<void> useDevice(String name) async {
    await GStorage.histories.clear();
    await GStorage.putSetting(SettingsKeys.accountSyncEnable, true);
    await GStorage.putSetting(SettingsKeys.webDavEnableHistory, true);
    await GStorage.putSetting(SettingsKeys.historySyncDeviceId, name);
    await GStorage.putSetting(
      SettingsKeys.historySyncSnapshotInitialized,
      false,
    );
    webDav.client = client;
    webDav.initialized = true;
    // 走真实同步路径需要本地临时目录已就绪（正常由 init() 建立）。
    webDav.webDavLocalTempDirectory = Directory(
      '${tempDir.path}/cloudSyncTemp',
    );
    await webDav.webDavLocalTempDirectory.create(recursive: true);
  }

  setUp(() async {
    client = _MemoryClient();
    await GStorage.resetSettings([
      SettingsKeys.accountSyncEnable,
      SettingsKeys.webDavEnableHistory,
      SettingsKeys.webDavEnable,
      SettingsKeys.historySyncDeviceId,
      SettingsKeys.historySyncSnapshotInitialized,
      SettingsKeys.historySyncSequence,
    ]);
  });

  test('a new device receives the watched episode from the cloud', () async {
    // 设备 A：一开始就看到第 75 集。
    await useDevice('device-a');
    await GStorage.histories.put(historyKey, _history(episode: 75));
    await webDav.syncHistory();

    expect(client.files, isNotEmpty, reason: '首次同步应上传快照或日志');
    expect(
      client.files.values.join(),
      contains('"lastWatchEpisode":75'),
      reason: '云端必须记录第 75 集',
    );

    // 设备 A 继续看到第 76 集，再次同步。
    await GStorage.histories.put(historyKey, _history(episode: 76));
    await webDav.syncHistory();
    expect(
      client.files.values.join(),
      contains('"lastWatchEpisode":76'),
      reason: '之后的进度也必须回写云端，而不是只写一次快照',
    );

    // 设备 B：全新安装，登录同一账号后同步。
    await useDevice('device-b');
    await webDav.syncHistory();

    final synced = GStorage.histories.get(historyKey);
    expect(synced, isNotNull, reason: '新设备必须拿到这条观看记录');
    expect(
      synced!.lastWatchEpisode,
      76,
      reason: '新设备应同步到最新观看集数',
    );
    expect(synced.progresses.keys, contains(76));
  });
}

History _history({required int episode}) {
  final history = History(
    _item(),
    episode,
    'plugin',
    DateTime.fromMillisecondsSinceEpoch(1700000000000 + episode),
    'https://example.com/video',
    'EP$episode',
  );
  history.progresses[episode] = Progress(
    episode,
    0,
    episode * 1000,
    updatedAtMs: 1700000000000 + episode,
  );
  return history;
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

class _MemoryClient implements webdav.Client {
  final files = <String, String>{};

  @override
  Future<void> mkdir(String path, [CancelToken? cancelToken]) async {}

  @override
  Future<List<webdav.File>> readDir(
    String path, [
    CancelToken? cancelToken,
  ]) async {
    return [
      for (final entry in files.entries)
        if (entry.key.startsWith('$path/'))
          webdav.File(
            name: entry.key.substring(path.length + 1),
            isDir: false,
            size: entry.value.length,
          ),
    ];
  }

  @override
  Future<void> read2File(
    String path,
    String savePath, {
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final contents = files[path];
    if (contents == null) throw StateError('File missing: $path');
    await File(savePath).writeAsString(contents);
  }

  @override
  Future<void> writeFromFile(
    String localFilePath,
    String path, {
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) async {
    files[path] = await File(localFilePath).readAsString();
  }

  @override
  Future<void> remove(String path, [CancelToken? cancelToken]) async {
    files.remove(path);
  }

  @override
  Future<void> rename(
    String oldPath,
    String newPath,
    bool overwrite, [
    CancelToken? cancelToken,
  ]) async {
    final contents = files.remove(oldPath);
    if (contents == null) throw StateError('File missing: $oldPath');
    files[newPath] = contents;
  }

  @override
  void setHeaders(Map<String, dynamic> headers) {}

  @override
  Future<void> ping([CancelToken? cancelToken]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}
