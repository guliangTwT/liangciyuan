import 'package:kazumi/services/network/acceleration_mode.dart';
import 'package:kazumi/services/storage/storage.dart';

enum BangumiAcceleration implements AccelerationMode {
  direct,
  ech,
  mirror;

  static BangumiAcceleration get current =>
      values.asNameMap()[GStorage.getSetting(
        SettingsKeys.bangumiAcceleration,
      )] ??
      // ECH 是国内直连 bgm.tv 的推荐默认：实测可访问条目/图片/搜索；
      // 镜像后端不再转发条目详情且受保护接口需要签名，仅保留给手选用户。
      (GStorage.getSetting(SettingsKeys.enableBangumiProxy)
          ? BangumiAcceleration.ech
          : BangumiAcceleration.direct);

  @override
  String get label => switch (this) {
    direct => '直连',
    ech => 'ECH',
    mirror => '镜像',
  };

  @override
  String get description => switch (this) {
    direct => '访问官方接口',
    ech => '加密握手（推荐）',
    mirror => '镜像接口',
  };
}
