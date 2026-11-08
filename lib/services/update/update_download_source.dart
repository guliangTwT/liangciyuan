enum UpdateDownloadSource {
  direct,
  mirror;

  // 主源是 GitHub Release 的直链；mirror 用于加速前缀或 Codeberg 后备源。
  String get label => switch (this) {
    direct => '直连',
    mirror => '镜像',
  };
}