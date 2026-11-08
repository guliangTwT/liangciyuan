enum UpdateDownloadSource {
  direct,
  mirror;

  // 主源是 Codeberg Release 的直链；mirror 留给以后接入加速/备份源。
  String get label => switch (this) {
    direct => '直连',
    mirror => '镜像',
  };
}