import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 以静默方式启动 Windows 安装包。
///
/// 我们发布的安装包是 Inno Setup，支持命令行开关：
/// - `/SILENT` 不显示向导（仅进度窗口，可再加 `/VERYSILENT` 完全无界面）
/// - `/CLOSEAPPLICATIONS` 让安装器关闭正在运行的应用
/// - `/NORESTART` 安装后不自动重启系统
/// - `/SUPPRESSMSGBOXES` 抑制剩余对话框
///
/// 关键点是**必须提权启动**：安装器清单要求管理员权限，用
/// `Process.start` 会被拒绝（ERROR_ELEVATION_REQUIRED / 740），
/// 因此走 `ShellExecuteW` 的 `runas` 动词触发 UAC。
/// 用户仍然需要点一次 UAC 的「是」——这是 Windows 的安全边界，无法绕过。
class SilentInstaller {
  SilentInstaller._();

  /// 返回 true 表示已成功拉起安装程序（不含用户拒绝 UAC 的情况）。
  static bool launchSilent(String installerPath, {bool verySilent = false}) {
    if (!Platform.isWindows) return false;
    if (!File(installerPath).existsSync()) {
      KazumiLogger().w('Update: installer not found: $installerPath');
      return false;
    }
    final parameters = [
      verySilent ? '/VERYSILENT' : '/SILENT',
      '/CLOSEAPPLICATIONS',
      '/NORESTART',
      '/SUPPRESSMSGBOXES',
    ].join(' ');
    try {
      final result = _shellExecuteRunAs(installerPath, parameters);
      // ShellExecute 返回值 > 32 表示成功。
      if (result > 32) return true;
      KazumiLogger().w('Update: ShellExecute returned $result');
      return false;
    } catch (e) {
      KazumiLogger().w('Update: silent install launch failed', error: e);
      return false;
    }
  }

  /// `ShellExecuteW(hwnd, "runas", file, params, cwd, SW_SHOWNORMAL)`。
  static int _shellExecuteRunAs(String file, String parameters) {
    final shell32 = DynamicLibrary.open('shell32.dll');
    final shellExecute = shell32.lookupFunction<
        IntPtr Function(
          IntPtr hwnd,
          Pointer<Utf16> lpOperation,
          Pointer<Utf16> lpFile,
          Pointer<Utf16> lpParameters,
          Pointer<Utf16> lpDirectory,
          Int32 nShowCmd,
        ),
        int Function(
          int hwnd,
          Pointer<Utf16> lpOperation,
          Pointer<Utf16> lpFile,
          Pointer<Utf16> lpParameters,
          Pointer<Utf16> lpDirectory,
          int nShowCmd,
        )>('ShellExecuteW');

    final operation = 'runas'.toNativeUtf16();
    final filePtr = file.toNativeUtf16();
    final paramsPtr = parameters.toNativeUtf16();
    final dirPtr = File(file).parent.path.toNativeUtf16();
    try {
      // SW_SHOWNORMAL = 1
      return shellExecute(0, operation, filePtr, paramsPtr, dirPtr, 1);
    } finally {
      malloc.free(operation);
      malloc.free(filePtr);
      malloc.free(paramsPtr);
      malloc.free(dirPtr);
    }
  }
}
