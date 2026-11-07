import 'dart:io';
import 'package:dio/dio.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/modules/history/history_sync.dart';
import 'package:kazumi/modules/danmaku/danmaku_shield_sync.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_change_module.dart';
import 'package:kazumi/services/sync/history_sync_service.dart';
import 'package:kazumi/services/account/account_service.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/services/sync/account_remote_client.dart';
import 'package:kazumi/services/sync/webdav_remote_file_commit.dart';
import 'package:kazumi/utils/async_serial_queue.dart';
import 'package:kazumi/utils/async_single_flight.dart';

class WebDav {
  static const String _syncRootPath = '/kazumiSync';
  static const String _historyRootPath = '$_syncRootPath/history';
  static const String _historyChangesPath = '$_historyRootPath/changes';
  static const String _historySnapshotPath = '$_historyRootPath/snapshot.json';
  static const String _danmakuShieldPath = '$_syncRootPath/danmakuShield';

  late String webDavURL;
  late String webDavUsername;
  late String webDavPassword;
  late Directory webDavLocalTempDirectory;
  late webdav.Client client;

  bool initialized = false;

  /// 当前 [client] 是用哪个令牌初始化出来的。
  /// 退出登录再换账号后令牌会变，必须据此重新建客户端，
  /// 否则会一直用旧令牌同步，直到重启应用都返回 401。
  String _clientToken = '';
  static const Duration _staleRunDirectoryAge = Duration(hours: 24);

  final AsyncSingleFlight<void> _historySyncSingleFlight =
      AsyncSingleFlight<void>();
  final AsyncSerialQueue _webDavOperationQueue = AsyncSerialQueue();
  final WebDavRemoteFileCommitter _remoteFileCommitter =
      const WebDavRemoteFileCommitter();

  bool get isHistorySyncing => _historySyncSingleFlight.isRunning;

  WebDav._internal();
  static final WebDav _instance = WebDav._internal();
  factory WebDav() => _instance;

  Future<void> init() => _runWebDavExclusive(_init);

  Future<void> _init() async {
    initialized = false;
    final directory = await getApplicationSupportDirectory();
    webDavLocalTempDirectory = Directory('${directory.path}/cloudSyncTemp');
    final account = AccountService()..ensureLoaded();
    if (!account.loggedIn) {
      _clientToken = '';
      throw Exception('请先登录凉次元账号');
    }
    client = AccountRemoteClient(token: account.token);
    _clientToken = account.token;
    try {
      await _ping();
      await _ensureRemoteDirectory(_syncRootPath);
      await _ensureLocalTempDirectory();
      initialized = true;
      KazumiLogger().i('CloudSync: account storage ready');
    } catch (e) {
      KazumiLogger().e('CloudSync: account storage ping failed', error: e);
      rethrow;
    }
  }

  /// 令牌变化或尚未初始化时重建客户端；已就绪时几乎零开销。
  Future<void> _ensureReady() async {
    final account = AccountService()..ensureLoaded();
    // 已初始化、且令牌没有变化时直接复用现有客户端；
    // 未登录或令牌已变化则重新初始化（未登录会由 _init 抛出提示）。
    if (initialized && account.token == _clientToken) {
      return;
    }
    initialized = false;
    await _init();
  }

  Future<T> _runWebDavExclusive<T>(Future<T> Function() action) {
    return _webDavOperationQueue.run(action);
  }

  /// 两次远端请求之间的最小间隔，避免云盘因突发请求返回 503/429。
  /// 自建账号服务不需要这种保护：每个请求都是 200ms 级 RTT 的直连，
  /// 人为等待只会把「同步」拖成十几秒。
  static const Duration _minRemoteRequestInterval = Duration(milliseconds: 150);
  static const Duration _accountRequestInterval = Duration.zero;
  static const int _maxRemoteAttempts = 4;

  /// 多个远端小文件的并发下载数；云盘对突发请求敏感，保持串行。
  int get _downloadConcurrency =>
      client is AccountRemoteClient ? 4 : 1;

  DateTime _nextRemoteRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  Duration get _remoteRequestInterval => client is AccountRemoteClient
      ? _accountRequestInterval
      : _minRemoteRequestInterval;

  /// 408/429/5xx 与连接类错误都值得重试；4xx 业务错误立即失败。
  static bool _isTransientRemoteError(Object error) {
    if (error is AccountException) {
      final code = error.statusCode;
      if (code != null) {
        return code == 408 || code == 429 || code >= 500;
      }
      // 无状态码的账号错误只有网络层失败值得重试；
      // 「请先登录」之类的本地错误重试只是白等。
      return AccountApi.isNetworkFailure(error);
    }
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return true;
        default:
          break;
      }
      final code = error.response?.statusCode;
      if (code != null) {
        return code == 408 || code == 429 || code >= 500;
      }
    }
    final text = error.toString();
    return RegExp(r'\b(408|429|5\d\d)\b').hasMatch(text);
  }

  Future<void> _paceRemoteRequest() async {
    final interval = _remoteRequestInterval;
    final now = DateTime.now();
    if (_nextRemoteRequestAt.isAfter(now)) {
      await Future<void>.delayed(_nextRemoteRequestAt.difference(now));
    }
    _nextRemoteRequestAt = DateTime.now().add(interval);
  }

  /// 远端调用统一走这里：限速 + 瞬时错误指数退避重试。
  Future<T> _remote<T>(Future<T> Function() action) async {
    var delay = const Duration(seconds: 1);
    for (var attempt = 1; ; attempt++) {
      await _paceRemoteRequest();
      try {
        return await action();
      } catch (error) {
        if (attempt >= _maxRemoteAttempts || !_isTransientRemoteError(error)) {
          rethrow;
        }
        KazumiLogger().w(
          'WebDav: transient remote error, retry $attempt/$_maxRemoteAttempts '
          'in ${delay.inMilliseconds}ms',
          error: error,
        );
        await Future<void>.delayed(delay);
        final next = delay.inMilliseconds * 2;
        delay = Duration(milliseconds: next > 8000 ? 8000 : next);
      }
    }
  }

  Future<List<webdav.File>> _readDir(String path) =>
      _remote(() => client.readDir(path));

  Future<void> _downloadFile(String remotePath, String localPath) =>
      _remote(() => client.read2File(remotePath, localPath));

  Future<void> _uploadFile(String localPath, String remotePath) =>
      _remote(() => client.writeFromFile(localPath, remotePath));

  Future<void> _removeFile(String path) => _remote(() => client.remove(path));

  Future<void> _renameFile(String from, String to, bool overwrite) =>
      _remote(() => client.rename(from, to, overwrite));

  Future<void> _mkdir(String path) => _remote(() => client.mkdir(path));

  Future<void> _ping() => _remote(() => client.ping());

  bool get isDanmakuShieldSyncEnabled =>
      GStorage.getSetting(SettingsKeys.accountSyncEnable) &&
      GStorage.getSetting(SettingsKeys.webDavEnableDanmakuShield);

  /// 把底层异常转成用户可读的一句话，便于定位同步失败的具体原因。
  static String describeError(Object error) {
    if (error is NetworkException) {
      final code = error.statusCode;
      if (code != null) {
        return _describeStatus(code);
      }
      return error.message;
    }
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code != null) {
        return _describeStatus(code);
      }
      return '网络异常，请检查连接';
    }
    final text = error
        .toString()
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^WebDavException:\s*'), '')
        .trim();
    if (text.isEmpty) {
      return '未知错误';
    }
    final status = RegExp(
      r'(?:status(?:\s*code)?|code)[^\d]{0,12}(\d{3})',
      caseSensitive: false,
    ).firstMatch(text)?.group(1);
    if (status != null) {
      return _describeStatus(int.parse(status));
    }
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  static String _describeStatus(int code) {
    if (code == 401 || code == 403) {
      return '登录状态已失效（$code），请重新登录凉次元账号';
    }
    if (code == 404) {
      return '云端数据不存在（404）';
    }
    if (code == 408) {
      return '请求超时（408），请检查网络后重试';
    }
    if (code == 429) {
      return '请求过于频繁（429），请稍后重试';
    }
    if (code == 503) {
      return '云同步服务暂时不可用（503），请稍后重试';
    }
    if (code >= 500) {
      return '服务器错误（$code），请稍后重试';
    }
    return '服务器返回 $code';
  }

  Future<void> syncDanmakuShield({
    required String deviceId,
    required Future<DanmakuShieldSyncState> Function(DanmakuShieldSyncState)
    merge,
  }) {
    // Queue every request: an edit during an upload needs another pass.
    return _runWebDavExclusive(() async {
      if (!isDanmakuShieldSyncEnabled) return;
      await _ensureReady();
      await _ensureLocalTempDirectory();
      await _ensureRemoteDirectory(_danmakuShieldPath);
      final runDirectory = await webDavLocalTempDirectory.createTemp(
        'danmaku-shield-sync-',
      );
      try {
        var remote = DanmakuShieldSyncState();
        final entries = await _readDir(_danmakuShieldPath);
        var index = 0;
        for (final entry in entries) {
          final name = entry.name ?? '';
          if (entry.isDir == true ||
              !RegExp(r'^[0-9a-f]{32}\.json$').hasMatch(name)) {
            continue;
          }
          final file = File('${runDirectory.path}/remote-${index++}.json');
          await _downloadFile('$_danmakuShieldPath/$name', file.path);
          // 任意远端文件损坏都中止整次同步：宁可不同步，也不覆盖远端数据。
          remote = remote.merge(
            DanmakuShieldSyncState.decode(await file.readAsString()),
          );
        }
        if (!isDanmakuShieldSyncEnabled) return;
        final merged = await merge(remote);
        final upload = File('${runDirectory.path}/local.json');
        await upload.writeAsString(merged.encode(), flush: true);
        // Per-device files prevent simultaneous uploads from losing edits.
        final destination = '$_danmakuShieldPath/$deviceId.json';
        await _publishRemoteFile(
          sourceFilePath: upload.path,
          destinationPath: destination,
          temporaryPath: '$destination.cache',
        );
      } finally {
        try {
          await runDirectory.delete(recursive: true);
        } catch (e) {
          KazumiLogger().w(
            'WebDav: failed to clean danmaku shield sync files',
            error: e,
          );
        }
      }
    });
  }

  Future<void> _updateBox(String boxName) async {
    var directory = await getApplicationSupportDirectory();
    // 复制前先落盘，降低把未完成的写入帧复制到远端的概率。
    if (boxName == 'collectibles') {
      await GStorage.collectibles.flush();
    } else if (boxName == 'collectchanges') {
      await GStorage.collectChanges.flush();
    }
    final localFilePath = '${directory.path}/hive/$boxName.hive';
    final tempFilePath = '${webDavLocalTempDirectory.path}/$boxName.tmp';
    final webDavPath = '$_syncRootPath/$boxName.tmp';
    await File(localFilePath).copy(tempFilePath);
    await _publishRemoteFile(
      sourceFilePath: tempFilePath,
      destinationPath: webDavPath,
      temporaryPath: '$webDavPath.cache',
    );
    try {
      await File(tempFilePath).delete();
    } catch (_) {}
  }

  Future<void> syncHistory() {
    return _historySyncSingleFlight.run(() async {
      try {
        await _runWebDavExclusive(() async {
          // 启动流程是 unawaited 的，播放页可能先于 init() 触发同步。
          await _ensureReady();
          await _syncHistory();
        });
      } catch (e) {
        KazumiLogger().e('WebDav: history sync failed', error: e);
        rethrow;
      }
    });
  }

  Future<void> _downloadBox(String boxName) async {
    String fileName = '$boxName.tmp';
    final existingFile = File('${webDavLocalTempDirectory.path}/$fileName');
    if (await existingFile.exists()) {
      await existingFile.delete();
    }
    await _downloadFile('$_syncRootPath/$fileName', existingFile.path);
  }

  Future<void> syncCollectibles() async {
    return _runWebDavExclusive(_syncCollectibles);
  }

  Future<void> _syncCollectibles() async {
    await _ensureReady();
    List<CollectedBangumi> remoteCollectibles = [];
    List<CollectedBangumiChange> remoteChanges = [];

    final files = await _readDir(_syncRootPath);
    final collectiblesExists = files.any(
      (file) => file.name == 'collectibles.tmp',
    );
    final changesExists = files.any(
      (file) => file.name == 'collectchanges.tmp',
    );
    if (!collectiblesExists && !changesExists) {
      await _updateBox('collectibles');
      if (GStorage.collectChanges.isNotEmpty) {
        await _updateBox('collectchanges');
      }
      return;
    }

    List<Future<void>> downloadFutures = [];
    if (collectiblesExists) {
      downloadFutures.add(
        _downloadBox('collectibles').catchError((e) {
          KazumiLogger().e('WebDav: download collectibles failed', error: e);
          throw Exception('WebDav: download collectibles failed');
        }),
      );
    }
    if (changesExists) {
      downloadFutures.add(
        _downloadBox('collectchanges').catchError((e) {
          KazumiLogger().e('WebDav: download collectchanges failed', error: e);
          throw Exception('WebDav: download collectchanges failed');
        }),
      );
    }
    if (downloadFutures.isNotEmpty) {
      await Future.wait(downloadFutures);
    }

    // 远端只有变更日志而没有收藏快照属于不一致状态：
    // 直接合并会把本地没有变更记录的收藏清空，因此隔离后以本地为准重建。
    if (changesExists && !collectiblesExists) {
      KazumiLogger().w(
        'WebDav: remote has collect changes without collectibles, rebuilding from local',
      );
      await _updateBox('collectibles');
      if (GStorage.collectChanges.isNotEmpty) {
        await _updateBox('collectchanges');
      }
      return;
    }

    try {
      if (collectiblesExists) {
        remoteCollectibles = await GStorage.getCollectiblesFromFile(
          '${webDavLocalTempDirectory.path}/collectibles.tmp',
        );
      }
      if (changesExists) {
        remoteChanges = await GStorage.getCollectChangesFromFile(
          '${webDavLocalTempDirectory.path}/collectchanges.tmp',
        );
      }
    } on FileSystemException {
      // 读写临时文件失败多为瞬时 IO 问题，保留远端数据并让调用方重试。
      rethrow;
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'WebDav: get collectibles failed, quarantining remote backup',
        error: e,
        stackTrace: stackTrace,
      );
      // 远端备份已损坏且每次都会以同样方式失败：隔离坏文件后重新上传本地数据。
      if (collectiblesExists) {
        await _quarantineCollectiblesBackup('collectibles.tmp');
      }
      if (changesExists) {
        await _quarantineCollectiblesBackup('collectchanges.tmp');
      }
      await _updateBox('collectibles');
      if (GStorage.collectChanges.isNotEmpty) {
        await _updateBox('collectchanges');
      }
      return;
    }
    if (remoteChanges.isNotEmpty || remoteCollectibles.isNotEmpty) {
      await GStorage.patchCollectibles(remoteCollectibles, remoteChanges);
    }
    await _updateBox('collectibles');
    if (GStorage.collectChanges.isNotEmpty) {
      await _updateBox('collectchanges');
    }
  }

  Future<void> _quarantineCollectiblesBackup(String remoteName) async {
    final quarantinePath =
        '$_syncRootPath/$remoteName.invalid.'
        '${DateTime.now().millisecondsSinceEpoch}';
    await _quarantineRemoteFile(
      sourcePath: '$_syncRootPath/$remoteName',
      quarantinePath: quarantinePath,
      description: 'collectibles backup $remoteName',
    );
  }

  Future<void> _syncHistory() async {
    await _ensureHistoryStorage();
    final historySync = HistorySyncService();
    final deviceId = await historySync.getDeviceId();
    final runDirectory = await _createHistorySyncRunDirectory();

    try {
      final downloads = await _downloadHistorySyncFiles(
        runDirectory: runDirectory,
        deviceId: deviceId,
      );
      final snapshotReadResult = await _readRemoteHistorySnapshot(
        historySync,
        downloads.snapshotFile,
      );
      var remoteSnapshot = snapshotReadResult.snapshot;
      var importedLegacyHistory = false;

      if (_isEmptyHistorySnapshot(remoteSnapshot) &&
          downloads.eventFiles.isEmpty) {
        importedLegacyHistory = await _tryImportLegacyHistory(runDirectory);
        if (importedLegacyHistory) {
          remoteSnapshot = await historySync.buildSnapshotFromLocal();
        }
      }

      final snapshotInitialized = GStorage.getSetting(
        SettingsKeys.historySyncSnapshotInitialized,
      );
      final localBatch = await historySync.prepareLocalLogs(
        runDirectory: runDirectory,
        forceCheckpoint:
            snapshotInitialized != true ||
            snapshotReadResult.needsRepair ||
            downloads.currentDeviceLogOversized ||
            importedLegacyHistory,
      );
      final mergedRemoteSnapshot = await _mergeRemoteHistoryEventFiles(
        historySync: historySync,
        snapshot: remoteSnapshot,
        eventFiles: downloads.eventFiles,
      );
      // Salvage interrupted local writes; reject malformed remote files as a whole.
      final mergedFromFiles = await historySync.mergeEventFiles(
        snapshot: mergedRemoteSnapshot,
        eventFiles: localBatch.files,
        inMemoryEvents: await historySync.buildLocalStateEvents(),
        tolerateMalformedLines: true,
      );

      final mergedSnapshot = await historySync.reconcileAndApplySnapshot(
        mergedFromFiles,
      );

      if (localBatch.shouldCheckpoint) {
        final snapshotFile = File(
          '${runDirectory.path}${Platform.pathSeparator}snapshot.json',
        );
        await historySync.writeSnapshotFile(mergedSnapshot, snapshotFile);
        await _publishHistorySnapshot(
          snapshotFile: snapshotFile,
          deviceId: deviceId,
        );
        await historySync.completeCheckpoint(localBatch);
        await _removeDeviceHistoryChanges(deviceId);
        await GStorage.putSetting(
          SettingsKeys.historySyncSnapshotInitialized,
          true,
        );
      } else {
        final uploadFile = await historySync.copyActiveLogForUpload(
          runDirectory,
        );
        if (uploadFile != null) {
          await _publishDeviceHistoryChanges(
            sourceFile: uploadFile,
            deviceId: deviceId,
          );
        }
      }
    } finally {
      try {
        if (await runDirectory.exists()) {
          await runDirectory.delete(recursive: true);
        }
      } catch (e) {
        KazumiLogger().w(
          'WebDav: failed to clean history sync temp directory',
          error: e,
        );
      }
    }
  }

  bool _isEmptyHistorySnapshot(HistorySyncSnapshot snapshot) {
    return snapshot.histories.isEmpty &&
        snapshot.itemVersions.isEmpty &&
        snapshot.progressVersions.isEmpty &&
        snapshot.deletedVersions.isEmpty &&
        snapshot.clearVersion == null;
  }

  Future<_HistorySnapshotReadResult> _readRemoteHistorySnapshot(
    HistorySyncService historySync,
    File? snapshotFile,
  ) async {
    if (snapshotFile == null) {
      return _HistorySnapshotReadResult(
        snapshot: HistorySyncSnapshot.empty(),
        needsRepair: false,
      );
    }

    try {
      return _HistorySnapshotReadResult(
        snapshot: await historySync.readSnapshotFile(snapshotFile),
        needsRepair: false,
      );
    } catch (e, stackTrace) {
      KazumiLogger().w(
        'WebDav: invalid history snapshot, rebuilding from event logs',
        error: e,
        stackTrace: stackTrace,
      );
      return _HistorySnapshotReadResult(
        snapshot: HistorySyncSnapshot.empty(),
        needsRepair: true,
      );
    }
  }

  Future<HistorySyncSnapshot> _mergeRemoteHistoryEventFiles({
    required HistorySyncService historySync,
    required HistorySyncSnapshot snapshot,
    required List<_DownloadedHistoryEventFile> eventFiles,
  }) async {
    final eventFilesByPath = {
      for (final eventFile in eventFiles)
        eventFile.localFile.path: eventFile.remoteName,
    };
    return historySync.mergeRemoteEventFiles(
      snapshot: snapshot,
      eventFiles: eventFiles.map((eventFile) => eventFile.localFile),
      onInvalidFile: (file, error, stackTrace) async {
        final remoteName = eventFilesByPath[file.path]!;
        KazumiLogger().w(
          'WebDav: invalid remote history event log $remoteName, skipping',
          error: error,
          stackTrace: stackTrace,
        );
        await _quarantineRemoteHistoryEventFile(remoteName);
      },
    );
  }

  Future<Directory> _createHistorySyncRunDirectory() async {
    await _cleanupStaleHistorySyncRunDirectories();
    return webDavLocalTempDirectory.createTemp('history-sync-run-');
  }

  Future<void> _cleanupStaleHistorySyncRunDirectories() async {
    await _ensureLocalTempDirectory();
    final staleBefore = DateTime.now().subtract(_staleRunDirectoryAge);
    await for (final entity in webDavLocalTempDirectory.list(
      followLinks: false,
    )) {
      if (entity is! Directory) {
        continue;
      }
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!name.startsWith('history-sync-run-')) {
        continue;
      }
      try {
        final stat = await entity.stat();
        // A recent directory may belong to another running Kazumi process.
        if (stat.modified.isAfter(staleBefore)) {
          continue;
        }
        await entity.delete(recursive: true);
      } catch (e) {
        KazumiLogger().w(
          'WebDav: failed to remove stale history sync directory $name',
          error: e,
        );
      }
    }
  }

  Future<_HistorySyncDownloads> _downloadHistorySyncFiles({
    required Directory runDirectory,
    required String deviceId,
  }) async {
    File? snapshotFile;
    final historyEntries = await _readDir(_historyRootPath);
    final hasSnapshot = historyEntries.any(
      (file) => file.name == 'snapshot.json',
    );
    if (hasSnapshot) {
      snapshotFile = File(
        '${runDirectory.path}${Platform.pathSeparator}remote-snapshot.json',
      );
      await _downloadFile(_historySnapshotPath, snapshotFile.path);
    }

    final eventFiles = <_DownloadedHistoryEventFile>[];
    var currentDeviceLogOversized = false;
    final changeEntries = await _readDir(_historyChangesPath);
    // 每个设备一个日志文件；设备多时串行下载会把 RTT 直接累加成十几秒。
    final changeNames = <String>[
      for (final entry in changeEntries)
        if ((entry.name ?? '').endsWith('.jsonl') && (entry.size ?? 0) > 0)
          entry.name!,
    ];
    final downloaded = await mapBounded(
      List<int>.generate(changeNames.length, (index) => index),
      (index) async {
        final name = changeNames[index];
        final localFile = File(
          '${runDirectory.path}${Platform.pathSeparator}'
          'remote-events-$index.jsonl',
        );
        await _downloadFile('$_historyChangesPath/$name', localFile.path);
        return _DownloadedHistoryEventFile(
          remoteName: name,
          localFile: localFile,
          oversized: name == '$deviceId.jsonl' &&
              await localFile.length() >
                  HistorySyncService.checkpointLogThresholdBytes,
        );
      },
      concurrency: _downloadConcurrency,
    );
    for (final item in downloaded) {
      eventFiles.add(item);
      if (item.oversized) currentDeviceLogOversized = true;
    }
    return _HistorySyncDownloads(
      snapshotFile: snapshotFile,
      eventFiles: eventFiles,
      currentDeviceLogOversized: currentDeviceLogOversized,
    );
  }

  Future<void> _publishHistorySnapshot({
    required File snapshotFile,
    required String deviceId,
  }) {
    return _publishRemoteFile(
      sourceFilePath: snapshotFile.path,
      destinationPath: _historySnapshotPath,
      temporaryPath: '$_historySnapshotPath.$deviceId.cache',
    );
  }

  Future<void> _publishDeviceHistoryChanges({
    required File sourceFile,
    required String deviceId,
  }) {
    final destinationPath = '$_historyChangesPath/$deviceId.jsonl';
    return _publishRemoteFile(
      sourceFilePath: sourceFile.path,
      destinationPath: destinationPath,
      temporaryPath: '$destinationPath.cache',
    );
  }

  Future<void> _publishRemoteFile({
    required String sourceFilePath,
    required String destinationPath,
    required String temporaryPath,
  }) async {
    // 账号云端是单次 PUT 原子替换：直接写目标即可，省掉
    // 「删临时文件 → 上传 → MOVE → 再删临时文件」的额外往返，
    // 同步 6 个文件时能少掉十几秒。
    if (client is AccountRemoteClient) {
      await _uploadFile(sourceFilePath, destinationPath);
      return;
    }
    await _remoteFileCommitter.replaceFile(
      sourceFilePath: sourceFilePath,
      temporaryPath: temporaryPath,
      destinationPath: destinationPath,
      remove: (path) => _removeFile(path),
      uploadFromFile: (sourceFilePath, remotePath) =>
          _uploadFile(sourceFilePath, remotePath),
      rename: (sourcePath, targetPath) =>
          _renameFile(sourcePath, targetPath, true),
      exists: _remoteEntryExists,
    );
  }

  Future<void> _removeDeviceHistoryChanges(String deviceId) async {
    final remotePath = '$_historyChangesPath/$deviceId.jsonl';
    try {
      await _removeFile(remotePath);
    } catch (e) {
      KazumiLogger().w(
        'WebDav: failed to remove checkpointed device history log',
        error: e,
      );
    }
  }

  Future<void> _quarantineRemoteHistoryEventFile(String remoteName) {
    final sourcePath = '$_historyChangesPath/$remoteName';
    final quarantinePath =
        '$sourcePath.invalid.'
        '${DateTime.now().millisecondsSinceEpoch}';
    return _quarantineRemoteFile(
      sourcePath: sourcePath,
      quarantinePath: quarantinePath,
      description: 'history event log $remoteName',
    );
  }

  Future<void> _ensureHistoryStorage() async {
    await _ensureLocalTempDirectory();
    await _ensureRemoteDirectory(_syncRootPath);
    await _ensureRemoteDirectory(_historyRootPath);
    await _ensureRemoteDirectory(_historyChangesPath);
  }

  Future<void> _ensureLocalTempDirectory() async {
    if (!await webDavLocalTempDirectory.exists()) {
      await webDavLocalTempDirectory.create(recursive: true);
    }
  }

  Future<void> _ensureRemoteDirectory(String path) async {
    try {
      await _mkdir(path);
    } catch (e) {
      if (!await _remoteEntryExists(path)) {
        rethrow;
      }
    }
  }

  Future<bool> _remoteEntryExists(String path) async {
    final normalized = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final index = normalized.lastIndexOf('/');
    final parent = index <= 0 ? '/' : normalized.substring(0, index);
    final name = normalized.substring(index + 1);
    try {
      final files = await _readDir(parent);
      return files.any((file) => file.name == name);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tryImportLegacyHistory(Directory runDirectory) async {
    final syncEntries = await _readDir(_syncRootPath);
    if (!syncEntries.any((file) => file.name == 'histories.tmp')) {
      return false;
    }

    const fileName = 'histories.tmp';
    final existingFile = File(
      '${runDirectory.path}${Platform.pathSeparator}$fileName',
    );
    try {
      await _downloadFile('$_syncRootPath/$fileName', existingFile.path);
    } catch (e, stackTrace) {
      KazumiLogger().w(
        'WebDav: failed to download legacy history backup, skipping import',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }

    try {
      await GStorage.patchHistory(existingFile.path);
      KazumiLogger().i('WebDav: imported legacy history backup');
      return true;
    } catch (e, stackTrace) {
      KazumiLogger().w(
        'WebDav: invalid legacy history backup, skipping import',
        error: e,
        stackTrace: stackTrace,
      );
      await _quarantineLegacyHistoryBackup();
      return false;
    }
  }

  Future<void> _quarantineLegacyHistoryBackup() async {
    final quarantinePath =
        '$_syncRootPath/histories.invalid.'
        '${DateTime.now().millisecondsSinceEpoch}.tmp';
    await _quarantineRemoteFile(
      sourcePath: '$_syncRootPath/histories.tmp',
      quarantinePath: quarantinePath,
      description: 'legacy history backup',
    );
  }

  /// MOVE 的兼容封装：部分服务器用 200 表示成功，客户端会误报失败。
  Future<void> _moveRemoteFile(String sourcePath, String targetPath) async {
    try {
      await _renameFile(sourcePath, targetPath, false);
      return;
    } catch (_) {
      final sourceGone = !await _remoteEntryExists(sourcePath);
      final targetPresent = await _remoteEntryExists(targetPath);
      if (!sourceGone || !targetPresent) {
        rethrow;
      }
    }
  }

  Future<void> _quarantineRemoteFile({
    required String sourcePath,
    required String quarantinePath,
    required String description,
  }) async {
    try {
      await _moveRemoteFile(sourcePath, quarantinePath);
      KazumiLogger().w('WebDav: moved invalid $description to $quarantinePath');
    } catch (e, stackTrace) {
      KazumiLogger().w(
        'WebDav: failed to quarantine invalid $description',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> ping() async {
    try {
      await _ping();
    } catch (e) {
      KazumiLogger().e('WebDav: WebDav ping failed', error: e);
      rethrow;
    }
  }
}

class _HistorySyncDownloads {
  const _HistorySyncDownloads({
    required this.snapshotFile,
    required this.eventFiles,
    required this.currentDeviceLogOversized,
  });

  final File? snapshotFile;
  final List<_DownloadedHistoryEventFile> eventFiles;
  final bool currentDeviceLogOversized;
}

class _DownloadedHistoryEventFile {
  const _DownloadedHistoryEventFile({
    required this.remoteName,
    required this.localFile,
    this.oversized = false,
  });

  final String remoteName;
  final File localFile;
  final bool oversized;
}

class _HistorySnapshotReadResult {
  const _HistorySnapshotReadResult({
    required this.snapshot,
    required this.needsRepair,
  });

  final HistorySyncSnapshot snapshot;
  final bool needsRepair;
}
