import 'dart:convert';
import 'dart:io';

import 'package:kazumi/modules/collect/collect_change_module.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/services/account/account_service.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider/path_provider.dart';

/// 账号云同步（第一版覆盖收藏）。
///
/// 复用 WebDAV 相同的 Hive 快照格式：上传整个 box 文件，下载后用
/// [GStorage.patchCollectibles] 做同样的合并，避免两套合并逻辑分叉。
class AccountSyncService {
  AccountSyncService._();

  static final AccountSyncService _instance = AccountSyncService._();

  factory AccountSyncService() => _instance;

  static const _collectibles = 'collectibles';
  static const _changes = 'collectchanges';

  Future<bool> syncCollectibles() async {
    final account = AccountService()..ensureLoaded();
    if (!account.loggedIn) return false;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _syncOnce(account.token);
        return true;
      } on AccountException catch (e) {
        // 云端在本次合并期间被其他设备更新：重新拉取后再试一次。
        if (e.statusCode == 409 && attempt == 0) {
          KazumiLogger().w('AccountSync: remote changed, retrying');
          continue;
        }
        rethrow;
      }
    }
    return false;
  }

  Future<void> _syncOnce(String token) async {
    final api = AccountApi.instance;
    final kinds = await api.listBlobs(token);
    final hasCollectibles = kinds.contains(_collectibles);
    final hasChanges = kinds.contains(_changes);

    if (!hasCollectibles && !hasChanges) {
      await _uploadLocal(token);
      return;
    }
    if (hasChanges && !hasCollectibles) {
      // 远端只有变更日志、没有快照，属于不完整状态：以本地为准重建。
      await _uploadLocal(token);
      return;
    }

    final temp = await Directory.systemTemp.createTemp('account-sync-');
    try {
      Future<File?> download(String kind) async {
        final blob = await api.getBlob(token, kind);
        if (blob == null) return null;
        final file = File('${temp.path}/$kind.tmp');
        await file.writeAsBytes(base64Decode(blob.payload));
        return file;
      }

      final collectiblesFile = await download(_collectibles);
      final changesFile = await download(_changes);

      final remoteCollectibles = <CollectedBangumi>[];
      final remoteChanges = <CollectedBangumiChange>[];
      try {
        if (collectiblesFile != null) {
          remoteCollectibles.addAll(
            await GStorage.getCollectiblesFromFile(collectiblesFile.path),
          );
        }
        if (changesFile != null) {
          remoteChanges.addAll(
            await GStorage.getCollectChangesFromFile(changesFile.path),
          );
        }
      } catch (e, stackTrace) {
        KazumiLogger().e(
          'AccountSync: remote collectible payload is invalid',
          error: e,
          stackTrace: stackTrace,
        );
        throw const AccountException('云端收藏数据损坏，已停止同步');
      }

      if (remoteCollectibles.isNotEmpty || remoteChanges.isNotEmpty) {
        await GStorage.patchCollectibles(remoteCollectibles, remoteChanges);
      }
      await _uploadLocal(token);
    } finally {
      try {
        await temp.delete(recursive: true);
      } catch (e) {
        KazumiLogger().w('AccountSync: temp cleanup failed', error: e);
      }
    }
  }

  Future<void> _uploadLocal(String token) async {
    await GStorage.collectibles.flush();
    await GStorage.collectChanges.flush();

    final directory = await getApplicationSupportDirectory();
    Future<String> readBox(String name) async {
      final file = File('${directory.path}/hive/$name.hive');
      if (!await file.exists()) return '';
      return base64Encode(await file.readAsBytes());
    }

    final collectibles = await readBox(_collectibles);
    if (collectibles.isEmpty) {
      throw const AccountException('本地收藏数据不存在');
    }

    final api = AccountApi.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    await api.putBlob(token, _collectibles, collectibles, updatedAt: now);

    final changes = await readBox(_changes);
    if (changes.isNotEmpty) {
      await api.putBlob(token, _changes, changes, updatedAt: now + 1);
    }
  }
}
