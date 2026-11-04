typedef WebDavRemoveRemoteFile = Future<void> Function(String path);
typedef WebDavUploadRemoteFile =
    Future<void> Function(String sourceFilePath, String remotePath);
typedef WebDavRenameRemoteFile =
    Future<void> Function(String sourcePath, String destinationPath);
typedef WebDavRemoteEntryExists = Future<bool> Function(String path);

/// Publishes a local file to WebDAV without assuming one particular server
/// flavour.
///
/// Compatibility notes:
/// - `webdav_client` only accepts 201/204/207 for MOVE, while some servers
///   answer a successful MOVE with 200. Such a move is treated as success
///   when the source disappeared and the destination appeared.
/// - Some servers reject MOVE onto an existing file: we retry after deleting
///   the destination.
/// - Some servers do not implement MOVE at all: we fall back to uploading
///   straight to the destination (PUT overwrites).
///
/// The uploaded temporary file is kept when every strategy fails so the new
/// content is not lost together with the previous remote file.
class WebDavRemoteFileCommitter {
  const WebDavRemoteFileCommitter();

  Future<void> replaceFile({
    required String sourceFilePath,
    required String temporaryPath,
    required String destinationPath,
    required WebDavRemoveRemoteFile remove,
    required WebDavUploadRemoteFile uploadFromFile,
    required WebDavRenameRemoteFile rename,
    required WebDavRemoteEntryExists exists,
  }) async {
    await _removeIfExists(temporaryPath, remove: remove, exists: exists);
    await uploadFromFile(sourceFilePath, temporaryPath);

    // 1. 标准服务器：直接覆盖式 MOVE。
    if (await _tryMove(
      temporaryPath,
      destinationPath,
      rename: rename,
      exists: exists,
    )) {
      return;
    }

    // 2. 拒绝覆盖的服务器：先删除目标再 MOVE。
    try {
      await _removeIfExists(destinationPath, remove: remove, exists: exists);
    } catch (_) {
      // 删除失败不阻断下一步（某些服务器对不存在的文件返回错误）。
    }
    if (await _tryMove(
      temporaryPath,
      destinationPath,
      rename: rename,
      exists: exists,
    )) {
      return;
    }

    // 3. 完全不支持 MOVE 的服务器：直接 PUT 覆盖目标。
    try {
      await uploadFromFile(sourceFilePath, destinationPath);
    } catch (_) {
      // 三条路径都失败，保留临时文件（新内容）后抛出原始错误。
      rethrow;
    }
    try {
      await remove(temporaryPath);
    } catch (_) {
      // 清理失败不影响结果，下次同步会重新覆盖该临时文件。
    }
  }

  /// Returns true when the move is done, including servers that report a
  /// successful MOVE with a status code `webdav_client` rejects (200).
  Future<bool> _tryMove(
    String sourcePath,
    String destinationPath, {
    required WebDavRenameRemoteFile rename,
    required WebDavRemoteEntryExists exists,
  }) async {
    try {
      await rename(sourcePath, destinationPath);
      return true;
    } catch (error) {
      try {
        final sourceGone = !await exists(sourcePath);
        if (sourceGone && await exists(destinationPath)) {
          return true;
        }
      } catch (_) {
        // 无法确认时按失败处理，交给下一种策略。
      }
      return false;
    }
  }

  Future<void> _removeIfExists(
    String path, {
    required WebDavRemoveRemoteFile remove,
    required WebDavRemoteEntryExists exists,
  }) async {
    try {
      await remove(path);
    } catch (_) {
      if (await exists(path)) {
        rethrow;
      }
    }
  }
}
