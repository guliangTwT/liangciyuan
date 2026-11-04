/// 收藏同步计划：收藏只在本地与 WebDAV 之间同步。
///
/// Bangumi 追番状态同步已移除，避免同一份收藏被两个远端双向覆盖。
class CollectSyncPlan {
  const CollectSyncPlan({
    required this.webDavEnabled,
    required this.webDavCollectiblesEnabled,
  });

  final bool webDavEnabled;
  final bool webDavCollectiblesEnabled;

  bool get shouldSyncWebDavCollectibles =>
      webDavEnabled && webDavCollectiblesEnabled;

  bool get canSync => shouldSyncWebDavCollectibles;
}
