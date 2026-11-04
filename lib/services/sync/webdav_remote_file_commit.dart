typedef WebDavRemoveRemoteFile = Future<void> Function(String path);
typedef WebDavUploadRemoteFile =
    Future<void> Function(String sourceFilePath, String remotePath);
typedef WebDavRenameRemoteFile =
    Future<void> Function(String sourcePath, String destinationPath);
typedef WebDavRemoteEntryExists = Future<bool> Function(String path);

/// Publishes a local file to WebDAV without assuming one particular server
/// flavour.
///
/// 1. Standard servers accept MOVE (201/204/207).
/// 2. Some servers answer a successful MOVE with 200, which `webdav_client`
///    reports as an error; the move is still treated as success when the
///    source disappeared and the destination appeared.
/// 3. Servers that reject MOVE onto an existing file, or do not implement
///    MOVE at all, fall back to a direct PUT overwrite.
///
/// The previous destination is never deleted up front, so a failed publish
/// cannot lose both the old and the new content.
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

    final moved = await _tryMove(
      temporaryPath,
      destinationPath,
      rename: rename,
      exists: exists,
    );
    if (moved) {
      return;
    }

    // MOVE unsupported or rejected: overwrite the destination with a plain
    // PUT. The old file stays intact until this write completes.
    await uploadFromFile(sourceFilePath, destinationPath);
    await _removeIfExists(temporaryPath, remove: remove, exists: exists);
  }

  Future<bool> _tryMove(
    String sourcePath,
    String destinationPath, {
    required WebDavRenameRemoteFile rename,
    required WebDavRemoteEntryExists exists,
  }) async {
    try {
      await rename(sourcePath, destinationPath);
      return true;
    } catch (_) {
      try {
        final sourceGone = !await exists(sourcePath);
        final destinationPresent = await exists(destinationPath);
        return sourceGone && destinationPresent;
      } catch (_) {
        return false;
      }
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
