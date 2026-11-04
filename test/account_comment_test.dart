import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/account/account_api.dart';

void main() {
  group('AccountComment', () {
    test('parses a full comment payload', () {
      final comment = AccountComment.fromJson({
        'id': 12,
        'content': '第一集就封神',
        'spoiler': true,
        'createdAt': 1793792373,
        'mine': true,
        'user': {
          'id': 1,
          'nickname': '顾凉',
          'avatarUrl': 'https://guliang.me/liangciyuan/api.php/v1/avatar/1?v=3',
        },
      });

      expect(comment.id, 12);
      expect(comment.content, '第一集就封神');
      expect(comment.spoiler, isTrue);
      expect(comment.createdAt, 1793792373);
      expect(comment.mine, isTrue);
      expect(comment.userId, 1);
      expect(comment.nickname, '顾凉');
      expect(comment.avatarUrl, contains('/v1/avatar/1'));
    });

    test('tolerates missing user and flags', () {
      final comment = AccountComment.fromJson({'id': 3, 'content': '旧数据'});

      expect(comment.content, '旧数据');
      expect(comment.spoiler, isFalse);
      expect(comment.mine, isFalse);
      expect(comment.userId, 0);
      expect(comment.nickname, isEmpty);
      expect(comment.avatarUrl, isEmpty);
    });
  });

  test('AccountCommentPage defaults to an empty list', () {
    const page = AccountCommentPage(total: 0, items: []);
    expect(page.total, 0);
    expect(page.items, isEmpty);
  });
}