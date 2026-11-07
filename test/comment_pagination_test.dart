import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/comment_pagination.dart';

/// 分页偏移的回归测试。
///
/// 曾经的缺陷：偏移取的是「去重后列表长度」。服务端返回的页里一旦含有
/// 已存在的条目，长度就不再增长，偏移卡死——用户点「加载更多」永远看不到
/// 后面的内容，单集讨论里还会把总数改小让按钮永久消失。
void main() {
  group('CommentPagination.nextOffset', () {
    test('advances by the number of items the server returned', () {
      expect(
        CommentPagination.nextOffset(
          currentOffset: 0,
          receivedItems: 20,
          total: 100,
        ),
        20,
      );
    });

    test('keeps advancing even when every item was a duplicate', () {
      // 服务端返回 20 条但全部已在列表中：偏移仍必须前进到 40，
      // 否则下一次还会请求同一页，永远取不到新内容。
      final offset = CommentPagination.nextOffset(
        currentOffset: 20,
        receivedItems: 20,
        total: 100,
      );
      expect(offset, 40);
      expect(
        CommentPagination.hasMore(offset: offset, total: 100),
        isTrue,
      );
    });

    test('an empty page ends pagination instead of retrying forever', () {
      final offset = CommentPagination.nextOffset(
        currentOffset: 40,
        receivedItems: 0,
        total: 100,
      );
      expect(offset, 100);
      expect(CommentPagination.hasMore(offset: offset, total: 100), isFalse);
    });
  });

  group('CommentPagination.hasMore', () {
    test('is false once the offset reaches the total', () {
      expect(CommentPagination.hasMore(offset: 100, total: 100), isFalse);
      expect(CommentPagination.hasMore(offset: 99, total: 100), isTrue);
    });
  });
}
