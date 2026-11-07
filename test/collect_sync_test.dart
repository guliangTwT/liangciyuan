import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/collect/collect_change_module.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_sync_merger.dart';
import 'package:kazumi/modules/collect/collect_type.dart';

void main() {
  group('CollectSyncMerger', () {
    test('merges local change log into cloud collectibles', () {
      final mergeResult = CollectSyncMerger.mergeWebDav(
        localCollectibles: [
          _collect(1, CollectType.watching, 10),
          _collect(2, CollectType.watched, 20),
          _collect(3, CollectType.abandoned, 30),
        ],
        localChanges: [
          _change(10, 1, 1, CollectType.watching, 10),
          _change(11, 2, 2, CollectType.watched, 20),
          _change(12, 3, 3, CollectType.abandoned, 30),
        ],
        remoteCollectibles: [
          _collect(2, CollectType.planToWatch, 5),
          _collect(3, CollectType.watching, 5),
          _collect(4, CollectType.onHold, 5),
        ],
        remoteChanges: [_change(9, 4, 1, CollectType.onHold, 5)],
      );

      expect(_typesById(mergeResult.collectibles), {
        1: CollectType.watching.value,
        2: CollectType.watched.value,
        4: CollectType.onHold.value,
      });
      expect(mergeResult.changes.map((change) => change.id), [9, 10, 11, 12]);
    });

    test('applies local changes on top of remote state', () {
      final mergeResult = CollectSyncMerger.mergeWebDav(
        localCollectibles: [
          _collect(1, CollectType.watching, 10),
          _collect(2, CollectType.watched, 20),
        ],
        localChanges: [
          _change(10, 1, 1, CollectType.watching, 10),
          _change(11, 2, 3, CollectType.none, 20),
        ],
        remoteCollectibles: [
          _collect(1, CollectType.planToWatch, 5),
          _collect(2, CollectType.planToWatch, 5),
        ],
        remoteChanges: const [],
      );

      expect(_typesById(mergeResult.collectibles), {
        1: CollectType.watching.value,
      });
      expect(mergeResult.changes.map((change) => change.id), [10, 11]);
    });
  });
}

CollectedBangumi _collect(int id, CollectType type, int timestamp) {
  return CollectedBangumi(
    _item(id),
    DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
    type.value,
  );
}

CollectedBangumiChange _change(
  int id,
  int bangumiId,
  int action,
  CollectType type,
  int timestamp,
) {
  return CollectedBangumiChange(id, bangumiId, action, type.value, timestamp);
}

BangumiItem _item(int id) {
  return BangumiItem(
    id: id,
    type: 2,
    name: 'subject $id',
    nameCn: '条目 $id',
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

Map<int, int> _typesById(List<CollectedBangumi> collectibles) {
  return {
    for (final collectible in collectibles)
      collectible.bangumiItem.id: collectible.type,
  };
}
