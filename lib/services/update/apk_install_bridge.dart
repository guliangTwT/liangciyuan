import 'package:flutter/services.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 应用内更新安装的系统通道。
///
/// Windows 与 Android 的能力不同，这里分开处理：
/// - **Windows**：安装包是 Inno Setup，支持 `/SILENT`，可直接静默覆盖安装，
///   用户只需通过一次 UAC。
/// - **Android**：普通应用**无法**真正静默安装，系统强制要求经过安装器
///   确认页（需要用户点一次「安装」）。能优化的是：用 `PackageInstaller`
///   代替 `ACTION_VIEW`，省掉「用哪个应用打开」的选择框，并能在装完后拿到
///   结果；同时提前引导用户开启「安装未知应用」权限。
class ApkInstallBridge {
  ApkInstallBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.predidit.kazumi/install');

  /// 是否已允许本应用安装 APK（Android 8.0+ 需用户手动开启）。
  static Future<bool> canRequestPackageInstalls() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'canRequestPackageInstalls',
      );
      return result ?? true;
    } on PlatformException catch (e) {
      KazumiLogger().w('Update: install permission check failed', error: e);
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// 跳转到系统设置，让用户为本应用开启「安装未知应用」。
  static Future<void> requestInstallPermission() async {
    try {
      await _channel.invokeMethod<void>('requestInstallPermission');
    } on PlatformException catch (e) {
      KazumiLogger().w('Update: request install permission failed', error: e);
    } on MissingPluginException {
      // 旧版本没有该通道，忽略。
    }
  }

  /// 用系统安装器安装 [path] 处的 APK。
  ///
  /// 返回 true 表示已将安装交给系统（用户可能还需在系统界面点一次确认）。
  static Future<bool> installApk(String path) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'installApk',
        {'path': path},
      );
      return result != null;
    } on PlatformException catch (e) {
      KazumiLogger().w('Update: install apk failed', error: e);
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
