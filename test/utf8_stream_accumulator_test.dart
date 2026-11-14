import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/utf8_stream_accumulator.dart';

/// 增量 UTF-8 解码的回归测试。
///
/// 曾经的缺陷：SyncPlay 的 socket 回调对每个 TCP 包直接 `utf8.decode(data)`。
/// TCP 按字节切包、不按字符切，一个汉字（3 字节）或 emoji（4 字节）很容易
/// 正好跨在两个包之间，此时 `utf8.decode` 抛 `FormatException`。那一行不在
/// 任何 try 内，异常冲出 socket 监听回调后，消息缓冲停在残片上，之后的所有
/// 消息都解析错位——中文聊天室会让整条连接永久失效，且没有任何提示。
void main() {
  group('跨包多字节字符', () {
    test('汉字被切成两半也能正确拼回', () {
      final bytes = utf8.encode('你好');
      final decoder = Utf8StreamAccumulator();
      // '你' = E4 BD A0，'好' = E5 A5 BD；从中间切开。
      final first = decoder.add(bytes.sublist(0, 4));
      final second = decoder.add(bytes.sublist(4));
      expect(first + second, '你好');
    });

    test('逐字节喂入也能还原完整文本', () {
      const text = '凉次元 SyncPlay 一起看';
      final bytes = utf8.encode(text);
      final decoder = Utf8StreamAccumulator();
      final buffer = StringBuffer();
      for (final byte in bytes) {
        buffer.write(decoder.add([byte]));
      }
      expect(buffer.toString(), text);
      expect(decoder.pendingBytes, 0, reason: '全部字节都应已解出');
    });

    test('emoji（4 字节）被切断也能拼回', () {
      final bytes = utf8.encode('🎬播放');
      final decoder = Utf8StreamAccumulator();
      // 在 emoji 的中间切开。
      final first = decoder.add(bytes.sublist(0, 2));
      final second = decoder.add(bytes.sublist(2));
      expect(first + second, '🎬播放');
    });

    test('不完整的字符不会被提前吐出替换符', () {
      final bytes = utf8.encode('你');
      final decoder = Utf8StreamAccumulator();
      // 只给前两个字节，第三个还没到。
      expect(decoder.add(bytes.sublist(0, 2)), isEmpty);
      expect(decoder.pendingBytes, 2, reason: '残缺字节应留在缓冲里等待');
      expect(decoder.add(bytes.sublist(2)), '你');
    });
  });

  group('正常路径', () {
    test('纯 ASCII 立即返回', () {
      final decoder = Utf8StreamAccumulator();
      expect(decoder.add(utf8.encode('abc')), 'abc');
      expect(decoder.pendingBytes, 0);
    });

    test('一次给完整文本直接返回', () {
      final decoder = Utf8StreamAccumulator();
      expect(decoder.add(utf8.encode('{"Hello":{}}')), '{"Hello":{}}');
    });

    test('空输入返回空串', () {
      final decoder = Utf8StreamAccumulator();
      expect(decoder.add(const []), '');
    });

    test('多次追加等价于一次追加', () {
      const text = '{"Chat":null,"Event":{"Username":"凉","Message":"你好呀 🎉"}}';
      // utf8.encode 返回定长 Uint8List，后续要切片消费，先转成可变的 List。
      final bytes = List<int>.of(utf8.encode(text));
      final decoder = Utf8StreamAccumulator();
      final chunks = <String>[];
      // 任意切分点，模拟真实 TCP 边界。
      for (final size in [1, 3, 7, 11, 5, 2, 13, 4]) {
        if (bytes.isEmpty) break;
        final take = size.clamp(1, bytes.length);
        chunks.add(decoder.add(bytes.sublist(0, take)));
        bytes.removeRange(0, take);
      }
      if (bytes.isNotEmpty) chunks.add(decoder.add(bytes));
      expect(chunks.join(), text);
    });
  });

  group('非法输入不抛异常', () {
    test('孤立续字节用替换符代替', () {
      final decoder = Utf8StreamAccumulator();
      // 0x80 是续字节，单独出现是非法的。
      expect(() => decoder.add([0x80]), returnsNormally);
    });

    test('截断的序列不会抛异常', () {
      final decoder = Utf8StreamAccumulator();
      // 声明 3 字节但只给 1 字节，且后续不再补齐。
      expect(() => decoder.add([0xE4]), returnsNormally);
      expect(decoder.pendingBytes, 1, reason: '应留下等待补齐');
    });
  });

  group('缓冲上限', () {
    test('滞留字节超过上限时报告溢出', () {
      // 单靠「不完整的 UTF-8 序列」测不到溢出：UTF-8 单字符最多 4 字节，
      // 滞留量天然被限制在 3 字节以内（第 4 个字节一到就会被解出）。
      // 所以上限只有设得比 3 更小时才会被触发——这也说明生产环境里
      // 8MB 的上限实际上只会在「对端持续发非法字节」时才有意义。
      final decoder = Utf8StreamAccumulator(maxPendingBytes: 2);
      expect(decoder.isOverflowing, isFalse);
      // 0xF0 声明 4 字节，给 3 字节后仍是残缺状态，会滞留。
      decoder.add([0xF0, 0x9F, 0x8E]);
      expect(decoder.pendingBytes, 3);
      expect(decoder.isOverflowing, isTrue, reason: '3 字节滞留 > 上限 2');
    });

    test('非法字节不会无限滞留', () {
      // 连续灌入孤立续字节：allowMalformed 会把它们解成替换符，
      // 不会让 pending 一直增长（否则生产上限就没意义了）。
      final decoder = Utf8StreamAccumulator();
      for (var i = 0; i < 100; i++) {
        decoder.add([0x80, 0x80, 0x80, 0x80]);
      }
      expect(decoder.isOverflowing, isFalse);
      expect(decoder.pendingBytes, lessThan(4));
    });

    test('reset 清空滞留字节', () {
      final decoder = Utf8StreamAccumulator();
      decoder.add([0xE4, 0xBD]);
      expect(decoder.pendingBytes, greaterThan(0));
      decoder.reset();
      expect(decoder.pendingBytes, 0);
      expect(decoder.add(utf8.encode('ok')), 'ok');
    });
  });
}
