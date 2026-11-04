/// 收藏同步计划：收藏只在本地与凉次元账号云端之间同步。
///
/// Bangumi 追番状态同步已移除，避免同一份收藏被两个远端双向覆盖。
class CollectSyncPlan {
  const CollectSyncPlan({
    required this.cloudEnabled,
    required this.collectiblesEnabled,
  });

  final bool cloudEnabled;
  final bool collectiblesEnabled;

  bool get shouldSyncCollectibles => cloudEnabled && collectiblesEnabled;

  bool get canSync => shouldSyncCollectibles;
}