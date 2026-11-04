import 'package:flutter/material.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/webdav.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/services/logging/logger.dart';

part 'collect_controller.g.dart';

class CollectController = _CollectController with _$CollectController;

abstract class _CollectController with Store {
  _CollectController(this._collectCrudRepository);

  final ICollectCrudRepository _collectCrudRepository;

  @observable
  ObservableList<CollectedBangumi> collectibles =
      ObservableList<CollectedBangumi>();

  void loadCollectibles() {
    collectibles.clear();
    collectibles.addAll(_collectCrudRepository.getAllCollectibles());
  }

  int getCollectType(BangumiItem bangumiItem) {
    return _collectCrudRepository.getCollectType(bangumiItem.id);
  }

  @action
  Future<void> addCollect(BangumiItem bangumiItem, {type = 1}) async {
    if (type == 0) {
      await deleteCollect(bangumiItem);
      return;
    }

    final int currentCollectType = getCollectType(bangumiItem);
    final int collectChangeAction = currentCollectType == 0 ? 1 : 2;

    await _collectCrudRepository.addCollectibleWithChange(
      bangumiItem,
      type,
      collectChangeAction,
    );
    loadCollectibles();
  }

  @action
  Future<void> deleteCollect(BangumiItem bangumiItem) async {
    await _deleteCollectLocally(bangumiItem);
  }

  Future<void> _deleteCollectLocally(BangumiItem bangumiItem) async {
    await _collectCrudRepository.deleteCollectibleWithChange(bangumiItem.id);
    loadCollectibles();
  }

  Future<void> updateLocalCollect(BangumiItem bangumiItem) async {
    await _collectCrudRepository.updateCollectible(bangumiItem);
    loadCollectibles();
  }

  void _reportSyncError(
    String message,
    ValueChanged<String> onError, {
    Object? error,
  }) {
    if (error != null) {
      KazumiLogger().e(message, error: error);
      onError('$message：${WebDav.describeError(error)}');
      return;
    }
    onError(message);
  }

  Future<bool> _connectWebDav(ValueChanged<String> onError) async {
    final bool webDavCollectEnable = GStorage.getSetting(
      SettingsKeys.webDavEnableCollect,
    );
    if (!webDavCollectEnable) {
      _reportSyncError('请开启 WebDAV 收藏同步', onError);
      return false;
    }
    if (!WebDav().initialized) {
      _reportSyncError('WebDAV 未连接，请检查配置', onError);
      return false;
    }
    try {
      await WebDav().ping();
    } catch (e) {
      _reportSyncError('WebDAV 连接失败，请检查网络或配置', onError, error: e);
      return false;
    }
    return true;
  }

  Future<bool> syncCollectibles({required ValueChanged<String> onError}) async {
    if (!await _connectWebDav(onError)) return false;
    try {
      await WebDav().syncCollectibles();
    } catch (e) {
      _reportSyncError('WebDAV 同步失败，请检查连接', onError, error: e);
      return false;
    }
    loadCollectibles();
    return true;
  }

  Future<void> migrateCollect() async {
    final favorites = _collectCrudRepository.getFavorites();
    if (favorites.isNotEmpty) {
      int count = 0;
      for (BangumiItem bangumiItem in favorites) {
        // Migration must work before Bangumi is initialized.
        final int currentCollectType = getCollectType(bangumiItem);
        final int collectChangeAction = currentCollectType == 0 ? 1 : 2;
        await _collectCrudRepository.addCollectibleWithChange(
          bangumiItem,
          1,
          collectChangeAction,
        );
        count++;
      }
      await _collectCrudRepository.clearFavorites();
      loadCollectibles();
      KazumiLogger().d(
        'GStorage: detected $count uncategorized favorites, migrated to collectibles',
      );
    }
  }
}
