import 'dart:convert';

/// 增量 UTF-8 解码：TCP 按字节切包，不按字符切。
///
/// 一个汉字在 UTF-8 里占 3 字节，emoji 占 4 字节，很可能正好跨在两个 TCP
/// 包之间。如果对每个包直接 `utf8.decode(data)`，遇到被切断的多字节字符
/// 会抛 `FormatException`——在 socket 监听回调里抛异常会直接冲掉整条连接的
/// 消息流，中文聊天室会让连接永久失效。
///
/// 这个类把字节累积起来，只解出**完整**的字符，把末尾不完整的序列留到
/// 下一次 [add] 补齐。真正的非法字节用替换符代替，不抛异常。
class Utf8StreamAccumulator {
  Utf8StreamAccumulator({this.maxPendingBytes = 8 * 1024 * 1024});

  /// 未解出字符的字节上限。对端持续发不含分隔符的数据时防止无限增长。
  final int maxPendingBytes;

  final List<int> _pending = <int>[];

  /// 当前滞留的字节数（测试与诊断用）。
  int get pendingBytes => _pending.length;

  /// 是否会因超过 [maxPendingBytes] 而溢出。
  bool get isOverflowing => _pending.length > maxPendingBytes;

  /// 追加一个字节块，返回这次能完整解出的文本。
  ///
  /// 末尾不完整的多字节序列不会出现在返回值里，也不会被丢弃——它们留在
  /// 内部缓冲，等后续 [add] 补齐。
  String add(List<int> bytes) {
    if (bytes.isEmpty) return '';
    _pending.addAll(bytes);
    if (_pending.isEmpty) return '';
    final end = _completePrefixLength(_pending);
    if (end <= 0) return '';
    final text = utf8.decode(
      _pending.sublist(0, end),
      allowMalformed: true,
    );
    _pending.removeRange(0, end);
    return text;
  }

  /// 清空未解出的字节。连接重建时调用，避免旧连接的残片污染新连接。
  void reset() => _pending.clear();

  /// 返回 [bytes] 中「所有完整 UTF-8 字符」的结束下标。
  ///
  /// 从末尾往回看最多 4 个字节：若最后一个字符的起始字节声明的长度超出
  /// 已有字节数，说明它还没收完，截断在这个起始字节之前。
  static int _completePrefixLength(List<int> bytes) {
    final length = bytes.length;
    // 从末尾往回最多找 4 个字节（UTF-8 单字符最长 4 字节）。
    for (var i = length - 1; i >= 0 && i >= length - 4; i--) {
      final byte = bytes[i];
      if (byte & 0x80 == 0) {
        // ASCII：本身完整，且它之后没有未完成的续字节（因为是从后往前
        // 遇到的第一个非续字节）。
        return i + 1;
      }
      if (byte & 0xC0 != 0x80) {
        // 起始字节：判断它需要的总长度是否已经到齐。
        final needed = _sequenceLength(byte);
        return i + needed <= length ? length : i;
      }
      // 续字节，继续往前找起始字节。
    }
    // 全是续字节（或长度 < 4 的孤立续字节序列）：无法定位边界，
    // 交给 allowMalformed 处理，整体解出来。
    return length;
  }

  /// 由 UTF-8 起始字节推断该字符的字节数。
  static int _sequenceLength(int leadByte) {
    if (leadByte >= 0xF0) return 4;
    if (leadByte >= 0xE0) return 3;
    if (leadByte >= 0xC0) return 2;
    return 1;
  }
}
