import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/dialog/update_available_dialog.dart';
import 'package:kazumi/request/clients/download_http_client.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/update/update_checksums.dart';
import 'package:kazumi/services/update/update_download_source.dart';
import 'package:kazumi/services/update/update_downloader.dart';
import 'package:kazumi/services/update/apk_install_bridge.dart';
import 'package:kazumi/services/update/silent_installer.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/version.dart';
enum InstallationType {
  windowsSetup('安装包'),
  windowsMsix('MSIX'),
  windowsPortable('ZIP'),
  linuxDeb('DEB'),
  linuxTar('TAR'),
  macosDmg('DMG'),
  androidApk('APK'),
  ios('IPA'),
  unknown('未知类型');

  const InstallationType(this.label);

  final String label;

  /// Types without a matching asset are updated from the release page.
  bool get downloadsInApp => getUpdateFilePatterns(this).isNotEmpty;
}

class UpdateInfo {
  final String version;
  final String description;
  final List<String> downloadUrls;
  final String releaseNotes;
  final String publishedAt;
  final InstallationType? installationType;
  final List<InstallationType> availableInstallationTypes;
  final List<dynamic> assets;

  UpdateInfo({
    required this.version,
    required this.description,
    required this.downloadUrls,
    required this.releaseNotes,
    required this.publishedAt,
    this.installationType,
    this.availableInstallationTypes = const [],
    this.assets = const [],
  });
  InstallationType get recommendedInstallationType {
    if (availableInstallationTypes.isNotEmpty) {
      return availableInstallationTypes.first;
    }
    return installationType ?? InstallationType.unknown;
  }
}

Map<String, dynamic>? getUpdateAssetForType(
  List<dynamic> assets,
  InstallationType type,
) {
  final patterns = getUpdateFilePatterns(type).map((p) => p.toLowerCase());

  try {
    final asset = assets.cast<Map<String, dynamic>>().firstWhere((asset) {
      final name = (asset['name'] as String?)?.toLowerCase() ?? '';
      return patterns.every((pattern) => name.contains(pattern));
    });
    return asset;
  } catch (_) {
    return null;
  }
}

String getUpdateFileHashFromAsset(Map<String, dynamic> asset) {
  final digest = asset['digest'] as String? ?? '';
  if (digest.startsWith('sha256:')) {
    return digest.substring(7);
  }
  return '';
}

List<String> getUpdateFilePatterns(InstallationType installationType) {
  switch (installationType) {
    case InstallationType.windowsSetup:
      // 例：liangciyuan-3.0.0-windows-x64-setup.exe
      return ['windows', 'x64-setup.exe'];
    case InstallationType.windowsMsix:
      return ['windows', '.msix'];
    case InstallationType.windowsPortable:
      return ['windows', '.zip'];
    case InstallationType.macosDmg:
      return ['macos', '.dmg'];
    case InstallationType.androidApk:
      return ['android', '.apk'];
    case InstallationType.linuxDeb:
    case InstallationType.linuxTar:
    case InstallationType.ios:
    case InstallationType.unknown:
      return [];
  }
}

class AutoUpdater {
  static final AutoUpdater _instance = AutoUpdater._internal();

  factory AutoUpdater() => _instance;

  AutoUpdater._internal();

  final DownloadHttpClient _downloadClient = DownloadHttpClient.instance;

  List<InstallationType> _detectAvailableInstallationTypes() {
    if (Platform.isWindows) {
      // Releases in this fork ship an Inno Setup installer; the portable ZIP
      // and signed MSIX stay as fallbacks for users who installed those.
      return [
        InstallationType.windowsSetup,
        InstallationType.windowsPortable,
        InstallationType.windowsMsix,
      ];
    }
    if (Platform.isLinux) {
      return [InstallationType.linuxDeb, InstallationType.linuxTar];
    }
    if (Platform.isMacOS) return [InstallationType.macosDmg];
    if (Platform.isIOS) return [InstallationType.ios];
    if (Platform.isAndroid) return [InstallationType.androidApk];
    return [InstallationType.unknown];
  }

  /// Drops installation types that have no matching asset in this release.
  /// This keeps the dialog from offering a type the repository does not publish.
  List<InstallationType> _installationTypesWithAssets(
    List<InstallationType> types,
    List<dynamic> assets,
  ) {
    final available = [
      for (final type in types)
        if (getUpdateAssetForType(assets, type) != null) type,
    ];
    return available.isEmpty ? types : available;
  }

  Future<UpdateInfo?> checkForUpdates() async {
    try {
      final data = await _latestRelease();

      if (!data.containsKey('tag_name')) {
        throw Exception('无效的响应数据');
      }

      // GitHub 的 tag 习惯带 `v` 前缀，版本比较只认纯数字。
      final remoteVersion = normalizeVersionTag('${data['tag_name']}');
      final currentVersion = ApiEndpoints.version;

      if (needUpdate(currentVersion, remoteVersion)) {
        // 资产列表为空时（只发了更新说明），别假装能应用内下载：
        // 让对话框退化成「前往下载」，跳转到发布页。
        final assets = (data['assets'] as List<dynamic>?) ?? const [];
        final availableTypes = assets.isEmpty
            ? const <InstallationType>[]
            : _installationTypesWithAssets(
                _detectAvailableInstallationTypes(),
                assets,
              );

        return UpdateInfo(
          version: remoteVersion,
          description: data['body'] ?? '发现新版本',
          downloadUrls: const [],
          releaseNotes: data['html_url'] ?? ApiEndpoints.releasePage,
          publishedAt: data['published_at'] ?? '',
          installationType: availableTypes.isEmpty
              ? InstallationType.unknown
              : availableTypes.first,
          availableInstallationTypes: availableTypes,
          assets: assets,
        );
      }

      return null;
    } catch (e) {
      KazumiLogger().e('Update: check for updates failed', error: e);
      rethrow;
    }
  }

  /// GitHub 为主源，Codeberg 为后备。
  ///
  /// 两家接口同形（`tag_name` / `body` / `html_url` / `assets[]`），
  /// 所以同一套解析逻辑通用。GitHub 拿不到（被墙、限流、仓库不可见）时
  /// 才去问 Codeberg，用户不会因为主源故障就检查不了更新。
  Future<Map<String, dynamic>> _latestRelease() async {
    final sources = [
      ApiEndpoints.latestApp,
      ApiEndpoints.latestAppFallback,
    ];
    Object? lastError;
    for (final base in sources) {
      try {
        final release = await _fetchRelease(base);
        await _attachChecksums(release);
        return release;
      } catch (e) {
        lastError = e;
        KazumiLogger().w('Update: release query failed for $base', error: e);
      }
    }
    throw lastError ?? Exception('Update check failed');
  }

  /// 加时间戳跳过中间缓存，发版后立刻生效。
  Future<Map<String, dynamic>> _fetchRelease(String base) async {
    final url = '$base?t=${DateTime.now().millisecondsSinceEpoch}';
    final raw = await _downloadClient.getPlain(
      url,
      headers: const {
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      },
      receiveTimeout: const Duration(seconds: 8),
    );
    final data = json.decode(raw);
    if (data is! Map) {
      throw Exception('Invalid update response');
    }
    return Map<String, dynamic>.from(data);
  }

  /// 把 `checksums.txt` 里的 SHA-256 补回每个资产。
  ///
  /// GitHub 的 release 自带 `digest` 字段，不再需要这一步；Codeberg 不返回
  /// 摘要，才要去读同一 release 里的 `checksums.txt`。读不到时保持原样：
  /// 下载入口会明确拒绝，并引导用户去发布页，而不是下一个无法验证的安装包。
  Future<void> _attachChecksums(Map<String, dynamic> release) async {
    final assets = release['assets'];
    if (assets is! List || assets.isEmpty) return;
    final missing = assets.whereType<Map>().where((asset) {
      final digest = (asset['digest'] as String?)?.trim() ?? '';
      return digest.isEmpty;
    });
    if (missing.isEmpty) return;
    final url = findChecksumAssetUrl(assets);
    if (url == null) {
      KazumiLogger().w('Update: release has no checksums asset');
      return;
    }
    try {
      final raw = await _downloadClient.getPlain(
        url,
        receiveTimeout: const Duration(seconds: 8),
      );
      final applied = applyChecksums(assets, parseChecksums(raw));
      KazumiLogger().i('Update: applied checksums to $applied asset(s)');
    } catch (e) {
      KazumiLogger().w('Update: checksums query failed', error: e);
    }
  }

  Future<void> autoCheckForUpdates() async {
    final autoUpdate = GStorage.getSetting(SettingsKeys.autoUpdate);
    if (!autoUpdate) return;

    try {
      final updateInfo = await checkForUpdates();
      if (updateInfo != null) {
        _showUpdateDialog(updateInfo, isAutoCheck: true);
      }
    } catch (e) {
      KazumiLogger().w('Update: auto check for updates failed', error: e);
    }
  }

  Future<void> manualCheckForUpdates() async {
    try {
      final updateInfo = await checkForUpdates();
      if (updateInfo != null) {
        _showUpdateDialog(updateInfo, isAutoCheck: false);
      } else {
        KazumiDialog.showToast(message: '当前已经是最新版本！');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '检查更新失败');
    }
  }

  Future<void> _showUpdateDialog(
    UpdateInfo updateInfo, {
    bool isAutoCheck = false,
  }) async {
    var disableAutoUpdate = false;
    final choice = await KazumiDialog.show<UpdateDialogChoice>(
      builder: (context) => UpdateAvailableDialog(
        updateInfo: updateInfo,
        onDisableAutoUpdateChanged: isAutoCheck
            ? (value) => disableAutoUpdate = value
            : null,
      ),
    );
    if (disableAutoUpdate) {
      GStorage.putSetting(SettingsKeys.autoUpdate, false);
      KazumiDialog.showToast(message: '已关闭自动更新');
    }
    if (choice != null) {
      _downloadUpdateWithType(updateInfo, choice.type, choice.source);
    }
  }

  Future<void> _downloadUpdateWithType(
    UpdateInfo updateInfo,
    InstallationType selectedType,
    UpdateDownloadSource source,
  ) async {
    try {
      if (!selectedType.downloadsInApp) {
        String releaseUrl = updateInfo.releaseNotes;
        if (releaseUrl.isEmpty) {
          releaseUrl = ApiEndpoints.releasePage;
        }
        // 打不开浏览器时必须给用户反馈，否则「前往下载」看起来像没响应。
        final opened = await launchUrl(
          Uri.parse(releaseUrl),
          mode: LaunchMode.externalApplication,
        );
        if (!opened) {
          KazumiDialog.showToast(message: '无法打开浏览器，请手动访问 $releaseUrl');
        }
        return;
      }

      final asset = getUpdateAssetForType(updateInfo.assets, selectedType);
      final downloadUrls = getUpdateDownloadUrlCandidatesFromAsset(
        asset,
        source,
      );
      if (asset == null || downloadUrls.isEmpty) {
        KazumiDialog.showToast(message: '没有找到 ${selectedType.label} 的下载链接');
        return;
      }

      final expectedHash = getUpdateFileHashFromAsset(asset);
      // 没有校验值就不下载：Codeberg 的 release 里必带 checksums.txt，
      // 读不到说明发布不完整或请求被拦截，让用户去发布页手动装更诚实。
      if (expectedHash.isEmpty) {
        KazumiDialog.showToast(
          message: '该版本缺少校验信息，正在打开发布页',
          duration: const Duration(seconds: 4),
        );
        final page = updateInfo.releaseNotes.isEmpty
            ? ApiEndpoints.releasePage
            : updateInfo.releaseNotes;
        await launchUrl(
          Uri.parse(page),
          mode: LaunchMode.externalApplication,
        );
        return;
      }
      final downloadInfo = UpdateInfo(
        version: updateInfo.version,
        description: updateInfo.description,
        downloadUrls: downloadUrls,
        releaseNotes: updateInfo.releaseNotes,
        publishedAt: updateInfo.publishedAt,
        installationType: selectedType,
        availableInstallationTypes: [selectedType],
        assets: updateInfo.assets,
      );

      // Android：下载前就确认「安装未知应用」权限。
      // 否则下完 35MB 才发现没权限，还得再跳一次设置。
      if (Platform.isAndroid &&
          selectedType == InstallationType.androidApk &&
          !await ApkInstallBridge.canRequestPackageInstalls()) {
        KazumiDialog.showToast(
          message: '开启「安装未知应用」后，更新才能自动完成安装',
          duration: const Duration(seconds: 5),
        );
        await ApkInstallBridge.requestInstallPermission();
        // 不阻塞下载：用户去设置授权的同时后台已在下载。
      }

      _downloadUpdate(downloadInfo, expectedHash);
    } catch (e) {
      KazumiDialog.showToast(message: '下载失败: ${e.toString()}');
      KazumiLogger().e('Update: download update failed', error: e);
    }
  }

  Future<void> _downloadUpdate(
    UpdateInfo updateInfo,
    String expectedHash,
  ) async {
    if (_downloadDialogs.isRunning) return;
    await _downloadDialogs.run(
      (task) async {
        _downloadProgress.value = 0;
        final cancelToken = CancelToken();
        final downloadPath = await task.loading(
          action: () => _downloadFile(
            updateInfo.downloadUrls,
            updateInfo.version,
            expectedHash,
            cancelToken,
          ),
          onCancel: cancelToken.cancel,
          builder: (context) {
            return AlertDialog(
              title: const Text('正在下载更新'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: _downloadProgress,
                    builder: (context, value, child) {
                      return Column(
                        children: [
                          LinearProgressIndicator(value: value),
                          const SizedBox(height: 8),
                          Text('${(value * 100).toStringAsFixed(1)}%'),
                        ],
                      );
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => KazumiDialog.dismiss(context: context),
                  child: const Text('取消'),
                ),
              ],
            );
          },
        );

        _showDownloadCompleteDialog(downloadPath, updateInfo);
      },
      onError: (e, stackTrace) {
        final errorMessage = getUpdateDownloadErrorMessage(e);

        KazumiDialog.show(
          builder: (context) {
            return AlertDialog(
              title: const Text('下载失败'),
              content: Text(errorMessage),
              actions: [
                TextButton(
                  onPressed: () => KazumiDialog.dismiss(context: context),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );

        KazumiLogger().e(
          'Update: download failed | source=${updateInfo.downloadUrls.join(', ')} | '
          '${describeUpdateDownloadError(e, stackTrace)}',
          error: e,
        );
      },
    );
  }

  final ValueNotifier<double> _downloadProgress = ValueNotifier(0.0);
  final _downloadDialogs = KazumiDialogController();

  /// 「立即安装」之后会发生什么，按平台如实说明。
  ///
  /// Windows 走 Inno Setup 的静默开关，只有 UAC 需要确认；
  /// Android 的系统限制决定了必须由用户在系统安装器点一次「安装」，
  /// 这里不掩饰这一点，避免用户以为「说好的静默呢」。
  String _installHintFor(UpdateInfo updateInfo) {
    final type = updateInfo.recommendedInstallationType;
    if (Platform.isWindows && type == InstallationType.windowsSetup) {
      return '将静默安装并自动退出，只需在系统提示里允许一次';
    }
    if (Platform.isAndroid) {
      return '应用会退出，随后在系统安装界面点一次「安装」即可';
    }
    return '安装过程中应用将会退出';
  }

  void _showDownloadCompleteDialog(String filePath, UpdateInfo updateInfo) {
    KazumiDialog.show(
      builder: (context) {
        return AlertDialog(
          title: const Text('下载完成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text('新版本 ${updateInfo.version} 已下载完成')),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _installHintFor(updateInfo),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '文件位置:',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      filePath,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(),
              child: Text(
                '稍后安装',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            if (isDesktop())
              TextButton(
                onPressed: () {
                  KazumiDialog.dismiss(context: context);
                  _revealInFileManager(filePath);
                },
                child: const Text('打开文件夹'),
              ),
            TextButton(
              onPressed: () {
                KazumiDialog.dismiss();
                _installUpdate(
                  filePath,
                  updateInfo.recommendedInstallationType,
                );
              },
              child: const Text('立即安装'),
            ),
          ],
        );
      },
    );
  }

  Future<String> _downloadFile(
    List<String> urls,
    String version,
    String expectedHash,
    CancelToken cancelToken,
  ) async {
    // 放在应用支持目录而不是系统临时目录：临时目录会被系统/OEM 清理策略
    // 随时删掉，用户「稍后安装」或安装时点错取消后就得重新下 35MB。
    // 这个目录保持到下一次成功安装，downloadUpdateFile 会复用校验过的文件。
    final baseDir = await getApplicationSupportDirectory();
    final updateDir = Directory('${baseDir.path}/updates');
    if (!await updateDir.exists()) {
      await updateDir.create(recursive: true);
    }
    final filePath =
        '${updateDir.path}/${_getFileNameFromUrl(urls.first, version)}';
    // 测速、择优、分块并行下载与校验都由 downloadUpdateFile 内部处理。
    final result = await downloadUpdateFile(
      urls: urls,
      filePath: filePath,
      expectedHash: expectedHash,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        _downloadProgress.value = total > 0 ? received / total : 0;
      },
    );
    // 下载**成功后**才清理旧版本：放在下载之前的话，一旦这次下载失败或被取消，
    // 上一份已经校验通过的安装包已经被删掉，用户两手空空。
    await _pruneOldUpdateFiles(
      updateDir,
      keepFileName: filePath.split('/').last,
    );
    return result;
  }

  /// 只保留当前版本的安装包，其余删除。
  Future<void> _pruneOldUpdateFiles(
    Directory dir, {
    required String keepFileName,
  }) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        if (entity.path.split(Platform.pathSeparator).last == keepFileName) {
          continue;
        }
        await entity.delete();
      }
    } catch (e) {
      KazumiLogger().w('Update: failed to prune old update files', error: e);
    }
  }

  void _installUpdate(
    String filePath,
    InstallationType installationType,
  ) async {
    try {
      if (Platform.isWindows) {
        if (installationType == InstallationType.windowsSetup) {
          // 静默覆盖安装：先让启动器盯着本进程退出，再由它拉起安装包。
          //
          // 不能直接启动安装包：安装器的 AppMutex 与主程序同名，只要主程序
          // 还活着就会弹「请先关闭正在运行的程序」，而 /SUPPRESSMSGBOXES
          // 会把它按「取消」，安装器直接中止（表现为界面一闪、版本没变）。
          KazumiDialog.showToast(message: '正在安装更新，请在系统提示中允许…');
          await Future<void>.delayed(const Duration(milliseconds: 120));
          final launched = SilentInstaller.launchAfterExit(filePath);
          if (launched) {
            // 启动器已在轮询本进程；尽快退出，让安装器通过互斥量检查。
            await Future<void>.delayed(const Duration(milliseconds: 150));
            exit(0);
          }
          // 启动器都拉不起来时退回可视化安装向导（此时仍会因互斥量提示，
          // 但至少用户能看到并手动关闭，不会静默失败）。
          KazumiLogger().w(
            'Update: launch-after-exit unavailable, falling back to wizard',
          );
          KazumiDialog.showToast(message: '无法自动安装，正在打开安装向导…');
        }
        if (installationType == InstallationType.windowsSetup ||
            installationType == InstallationType.windowsMsix) {
          // 安装器清单要求管理员权限；CreateProcess 对此类可执行文件返回
          // ERROR_ELEVATION_REQUIRED（740），launchUrl 走 ShellExecute
          // 才能触发 UAC 弹出安装向导。
          final Uri fileUri = Uri.file(filePath);
          // canLaunchUrl 在 Windows 上几乎恒为 true（只查 HKCR\file 有没有
          // URL Protocol），不能当作「打得开」的证据。真正要看的是
          // launchUrl 的返回值：false 表示没有关联程序，此时必须留在这里，
          // 否则安装器没起来而应用已经退出。
          final opened = await canLaunchUrl(fileUri) &&
              await launchUrl(fileUri);
          if (!opened) {
            KazumiLogger().w('Update: launch installer failed: $fileUri');
            KazumiDialog.showToast(
              message: '无法启动安装程序，请到下载目录手动运行',
              duration: const Duration(seconds: 5),
            );
            return;
          }
        } else {
          await Process.start('explorer.exe', [filePath], runInShell: true);
        }
        // 只留极短缓冲让 UAC/资源管理器接管，不再干等 1 秒。
        await Future<void>.delayed(const Duration(milliseconds: 250));
        exit(0);
      } else if (Platform.isMacOS) {
        if (filePath.endsWith('.dmg')) {
          await Process.start('open', [filePath]);
          exit(0);
        }
        // 不是 .dmg 时不要静默结束：否则用户点「立即安装」毫无反应。
        KazumiDialog.showToast(message: '无法识别该安装包，请到下载目录手动安装');
      } else if (Platform.isAndroid) {
        // 先确认「安装未知应用」权限；未开启时引导用户去设置，
        // 否则系统安装器会直接拒绝，看起来像「点了没反应」。
        if (!await ApkInstallBridge.canRequestPackageInstalls()) {
          KazumiDialog.showToast(
            message: '请先允许「安装未知应用」，然后再点一次安装',
            duration: const Duration(seconds: 5),
          );
          await ApkInstallBridge.requestInstallPermission();
          return;
        }
        final handedOff = await ApkInstallBridge.installApk(filePath);
        if (!handedOff) {
          // 系统通道不可用时退回 open_filex（会弹「用哪个应用打开」）。
          final result = await OpenFilex.open(filePath);
          if (result.type != ResultType.done) {
            KazumiDialog.showToast(message: '无法打开安装文件: ${result.message}');
            return;
          }
        }
      }
    } catch (e) {
      KazumiDialog.showToast(message: '启动安装程序失败: ${e.toString()}');
      KazumiLogger().e('Update: launch installer failed', error: e);
    }
  }

  void _revealInFileManager(String filePath) async {
    try {
      final type = await FileSystemEntity.type(filePath);
      String targetDirOrFile;
      if (type == FileSystemEntityType.notFound) {
        KazumiDialog.showToast(message: '文件或目录不存在');
        return;
      } else if (type == FileSystemEntityType.directory) {
        targetDirOrFile = filePath;
      } else {
        targetDirOrFile = File(filePath).parent.path;
      }

      if (Platform.isWindows) {
        if (type == FileSystemEntityType.file) {
          final arg = '/select,${filePath.replaceAll('/', r'\')}';
          await Process.start('explorer.exe', [arg], runInShell: true);
        } else {
          await Process.start('explorer.exe', [
            targetDirOrFile.replaceAll('/', r'\'),
          ], runInShell: true);
        }
      } else if (Platform.isMacOS) {
        if (type == FileSystemEntityType.file) {
          await Process.start('open', ['-R', filePath]);
        } else {
          await Process.start('open', [targetDirOrFile]);
        }
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [targetDirOrFile]);
      } else {
        KazumiDialog.showToast(message: '此平台不支持通过此方法打开文件管理器');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '无法打开文件管理器');
      KazumiLogger().w('Update: reveal in file manager failed', error: e);
    }
  }

  String _getFileNameFromUrl(String url, String version) {
    final uri = Uri.parse(url);
    final fileName = uri.pathSegments.last;

    if (fileName.isNotEmpty) {
      return fileName;
    }
    String extension = '';
    if (Platform.isWindows) {
      extension = '.exe';
    } else if (Platform.isMacOS) {
      extension = '.dmg';
    } else if (Platform.isLinux) {
      extension = '.deb';
    } else if (Platform.isAndroid) {
      extension = '.apk';
    }
    return '凉次元-$version$extension';
  }
}
