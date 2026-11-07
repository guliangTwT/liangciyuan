import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/services/account/account_api.dart';

/// 「凉次元作者」称号的解析与展示。
///
/// 称号只由服务端下发；客户端负责把它带进评论卡片、弹幕文本和个人主页。
void main() {
  group('AccountComment title', () {
    test('reads the title from the nested user object', () {
      final comment = AccountComment.fromJson({
        'id': 1,
        'content': '这条番很不错',
        'user': {
          'id': 7,
          'nickname': '顾凉',
          'title': '凉次元作者',
          'avatarUrl': '',
        },
      });

      expect(comment.title, '凉次元作者');
      expect(comment.nickname, '顾凉');
    });

    test('defaults to empty when the server sends no title', () {
      final comment = AccountComment.fromJson({
        'id': 2,
        'content': '普通吐槽',
        'user': {'id': 8, 'nickname': '路人'},
      });

      expect(comment.title, isEmpty);
    });
  });

  group('AccountDanmaku title', () {
    test('parses nickname and title', () {
      final danmaku = AccountDanmaku.fromJson({
        'id': 3,
        'positionMs': 12000,
        'mode': 1,
        'color': 0xFFFFFF,
        'content': '前方高能',
        'userId': 7,
        'nickname': '顾凉',
        'title': '凉次元作者',
      });

      expect(danmaku.nickname, '顾凉');
      expect(danmaku.title, '凉次元作者');
    });

    test('toDanmakuEntry carries nickname and title', () {
      final entry = AccountDanmaku.fromJson({
        'id': 4,
        'positionMs': 5000,
        'content': '测试',
        'userId': 7,
        'nickname': '顾凉',
        'title': '凉次元作者',
      }).toDanmakuEntry();

      expect(entry.nickname, '顾凉');
      expect(entry.title, '凉次元作者');
      expect(entry.time, 5);
    });
  });

  group('DanmakuEntry.displayText', () {
    test('shows title before nickname', () {
      final entry = DanmakuEntry(
        message: '说得对',
        time: 1,
        type: 1,
        color: const Color(0xFFFFFFFF),
        source: 'liangciyuan',
        nickname: '顾凉',
        title: '凉次元作者',
      );

      expect(entry.displayText, '[凉次元作者] 顾凉：说得对');
    });

    test('shows nickname only when there is no title', () {
      final entry = DanmakuEntry(
        message: '普通',
        time: 1,
        type: 1,
        color: const Color(0xFFFFFFFF),
        source: 'liangciyuan',
        nickname: '路人',
      );

      expect(entry.displayText, '路人：普通');
    });

    test('keeps the raw message when nothing is known about the sender', () {
      final entry = DanmakuEntry(
        message: '原始文本',
        time: 1,
        type: 1,
        color: const Color(0xFFFFFFFF),
        source: 'liangciyuan',
      );

      expect(entry.displayText, '原始文本');
    });

    test('own sent danmaku stays unprefixed', () {
      // 本地回显不设置 nickname/title，避免自己的弹幕也带上名字。
      final entry = DanmakuEntry(
        message: '我发的',
        time: 1,
        type: 1,
        color: const Color(0xFFFFFFFF),
        source: 'liangciyuan',
      );

      expect(entry.displayText, '我发的');
    });
  });
}
