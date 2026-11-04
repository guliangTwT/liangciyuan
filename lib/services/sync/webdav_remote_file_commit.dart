typedef WebDavRemoveRemoteFile = Future<void> Function(String path);
typedef WebDavUploadRemoteFile = Future<void> Function(
  String sourceFilePath,
  String remotePath,
);
typedef WebDavRenameRemoteFile = Future<void> Function(
  String sourcePath,
  String destinationPath,
);
typedef WebDavRemoteEntryExists = Future<bool> Function(String path);

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
    await _removeIfExists(
      temporaryPath,
      remove: remove,
      exists: exists,
    );
    await uploadFromFile(sourceFilePath, temporaryPath);

    // 多数服务器支持 overwrite rename，直接覆盖可避免旧文件出现空窗。
    try {
      await rename(temporaryPath, destinationPath);
      return;
    } catch (_) {
      // 部分服务器拒绝覆盖已存在文件，退化为“备份旧文件 -> 替换”。
    }

    final backupPath = '$destinationPath.bak';
    await _removeIfExists(
      backupPath,
      remove: remove,
      exists: exists,
    );
    var backedUp = false;
    if (await exists(destinationPath)) {
      try {
        await rename(destinationPath, backupPath);
        backedUp = true;
      } on Exception {
        // 无法备份时退回删除，但仅在确认目标存在的情况下执行。
        await _removeIfExists(
          destinationPath,
          remove: remove,
          exists: exists,
        );
      }
    }

    try {
      await rename(temporaryPath, destinationPath);
    } catch (_) {
      // 替换失败时优先恢复旧文件；临时文件保留，避免新旧内容一起丢失。
      if (backedUp) {
        try {
          await rename(backupPath, destinationPath);
          backedUp = false;
        } on Exception {
          // 恢复失败则保留 .bak，供下次排查或手动恢复。
        }
      }
      rethrow;
    }
    if (backedUp) {
      await _removeIfExists(
        backupPath,
        remove: remove,
        exists: exists,
      );
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
