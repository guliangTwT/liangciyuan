/// 去重分页的偏移推进规则。
///
/// 列表会按 id 去重，因此**不能用列表长度当偏移**：一旦服务端返回的页里
/// 含有已存在的条目，长度就不再增长，偏移卡死，用户点「加载更多」也永远
/// 取不到后面的内容。这里统一按「服务端实际返回的条数」推进偏移。
class CommentPagination {
  CommentPagination._();

  /// 请求下一页时使用的偏移。
  static int nextOffset({
    required int currentOffset,
    required int receivedItems,
    required int total,
  }) {
    // 空页意味着服务端认为已到末尾；把偏移推到总数，避免反复请求同一页。
    if (receivedItems <= 0) return total;
    return currentOffset + receivedItems;
  }

  /// 是否还存在未拉取的页。
  static bool hasMore({required int offset, required int total}) {
    return offset < total;
  }
}
