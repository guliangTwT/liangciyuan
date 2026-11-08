import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/collect/collect_sync_dialog.dart';
import 'package:kazumi/services/sync/account_sync_service.dart';

void main() {
  group('同步步骤标签', () {
    test('步骤标题与同步结果使用同一个来源', () {
      // 曾经界面写「云端收藏」、结果写「收藏」，字符串永不相等，
      // 收藏同步成功后仍然显示「未完成」。这里锁死两者同源。
      for (final step in CollectSyncStep.values) {
        expect(step.title, step.content.label);
      }
    });

    test('每个内容的标签唯一', () {
      final labels = SyncContent.values.map((content) => content.label).toList();
      expect(labels.toSet().length, labels.length);
    });

    test('收藏这一步的标题是「云端收藏」', () {
      expect(CollectSyncStep.collect.title, '云端收藏');
    });

    test('三个步骤覆盖三种同步内容且不重复', () {
      final contents = CollectSyncStep.values.map((step) => step.content);
      expect(contents.toSet().length, CollectSyncStep.values.length);
      expect(contents, containsAll(SyncContent.values));
    });
  });
}