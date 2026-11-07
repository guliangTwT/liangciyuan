import 'package:flutter/material.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/utils/danmaku.dart';

class DanmakuEntry {
  // 弹幕内容
  String message;
  // 弹幕时间
  double time;
  // 弹幕类型 (1-普通弹幕，4-底部弹幕，5-顶部弹幕)
  int type;
  // 弹幕颜色
  Color color;
  // 弹幕来源
  String source;

  /// 发送者昵称（自建弹幕才有）；空字符串表示未知。
  String nickname;

  /// 发送者称号（如「凉次元作者」）；空字符串表示没有称号。
  String title;

  DanmakuEntry(
      {required this.message,
      required this.time,
      required this.type,
      required this.color,
      required this.source,
      this.nickname = '',
      this.title = ''});

  factory DanmakuEntry.fromJson(Map<String, dynamic> json) {
    String messageValue = json['m'];
    List<String> parts = json['p'].split(',');
    double timeValue = double.parse(parts[0]);
    int typeValue = int.parse(parts[1]);
    Color color = generateDanmakuColor(int.parse(parts[2]));
    String sourceValue = parts[3];
    return DanmakuEntry(
        time: timeValue,
        message: messageValue,
        type: typeValue,
        color: color,
        source: sourceValue);
  }

  /// 序列化为 JSON 格式 (与 fromJson 格式一致)
  Map<String, dynamic> toJson() {
    // 只存储 RGB 部分 (与 DanDanPlay API 格式一致)
    final colorValue = ((color.r * 255).toInt() << 16) |
        ((color.g * 255).toInt() << 8) |
        (color.b * 255).toInt();
    return {
      'm': message,
      'p': '$time,$type,$colorValue,$source',
    };
  }

  /// 实际绘制到画布上的文本：有称号/昵称时加前缀。
  ///
  /// 例：「[凉次元作者] 顾凉：说得对」。没有任何身份信息时原样返回，
  /// 避免给普通弹幕也加上多余前缀。
  String get displayText {
    final name = nickname.trim();
    final badge = title.trim();
    if (badge.isEmpty && name.isEmpty) return message;
    final prefix = [
      if (badge.isNotEmpty) '[$badge]',
      if (name.isNotEmpty) '$name：',
    ].join(' ');
    return '$prefix$message';
  }
}

/// 自建弹幕 → 播放器内部条目。
extension AccountDanmakuEntry on AccountDanmaku {
  DanmakuEntry toDanmakuEntry() {
    return DanmakuEntry(
      message: content,
      time: positionMs / 1000,
      type: mode,
      color: Color(0xFF000000 | (color & 0xFFFFFF)),
      source: 'liangciyuan',
      nickname: nickname,
      title: title,
    );
  }
}
