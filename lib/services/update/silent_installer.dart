import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 以静默方式启动 Windows 安装包。
///
/// 我们发布的安装包是 Inno Setup，支持命令行开关：
/// - `/SILENT` 不显示向导（仅进度窗口，可再加 `/VERYSILENT` 完全无界面）
/// - `/CLOSEAPPLICATIONS` 让安装器通过 Restart Manager 关闭应用
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
  ///
  /// 调用方**必须**在调用前退出自己，见 [launchAfterExit]。
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

  /// 启动一个**独立的**启动器，等当前进程退出后再运行安装包，装完再拉起应用。
  ///
  /// 为什么不能直接启动安装包：安装包原先带 `AppMutex=liangciyuan.win.mutex`，
  /// 与主程序的 `CreateMutex` 同名。只要主程序还活着，安装器就会弹
  /// 「请先关闭正在运行的程序」；而 `/SUPPRESSMSGBOXES` 会把这个对话框
  /// 自动按「取消」，安装器直接 `EAbort` 退出——表现就是点「立即安装」
  /// 后窗口一闪、版本没变。
  ///
  /// `/CLOSEAPPLICATIONS` 依赖 Restart Manager，对裸 `CreateMutex` 无效，
  /// 所以现在安装包改用 `CloseApplications=force`，并去掉了 `AppMutex`。
  /// 但为了不依赖 Restart Manager 的行为，这里仍然主动退出：
  ///
  /// 1. 写一个临时 .cmd，轮询等本进程 PID 消失（最多 [timeout]）；
  /// 2. 用 `start /wait` 拉起安装包并等它结束；
  /// 3. 安装完成后重新启动应用，用户不用自己再点一次。
  static bool launchAfterExit(
    String installerPath, {
    Duration timeout = const Duration(seconds: 30),
    bool verySilent = false,
  }) {
    if (!Platform.isWindows) return false;
    final installer = File(installerPath);
    if (!installer.existsSync()) {
      KazumiLogger().w('Update: installer not found: $installerPath');
      return false;
    }
    // 安装器会把 exe 放在 {app} 下；安装后用同目录的 exe 重启。
    final appExe = File(Platform.resolvedExecutable);
    final appName = Platform.resolvedExecutable
        .split(Platform.pathSeparator)
        .last;

    // 关键：交给 cmd 的路径必须是反斜杠。
    // 应用内部一律用 `/` 拼路径（updateDir.path + '/' + fileName），
    // 而 `start "" /wait "%INSTALLER%"` 对正斜杠路径会直接失败（实测 exit=1），
    // 安装器根本没起来，脚本随后又把旧版拉起来，表现为「更新完还是旧版本」。
    String winPath(String path) => path.replaceAll('/', r'\');

    final switches = [
      verySilent ? '/VERYSILENT' : '/SILENT',
      '/CLOSEAPPLICATIONS',
      '/NORESTART',
      '/SUPPRESSMSGBOXES',
    ].join(' ');

    try {
      final launcher = File(
        '${Directory.systemTemp.path}\\liangciyuan-update-$pid.cmd',
      );
      // 用 IMAGENAME 而不是 PID 判断：PID 在同一会话里可能被复用，
      // 而 `tasklist /fi "PID eq N"` 在部分系统上还会漏报，
      // 两种误判都会让启动器在应用仍运行时就去安装（安装器随即中止）。
      // 进程名唯一且稳定，配合 `find /i` 做忽略大小写匹配。
      final rounds = timeout.inSeconds;
      // 启动器写一个就绪标记，主进程确认它真的跑起来后才退出。
      // 否则 cmd 被策略/杀软拦下时，应用会误判成功并 exit(0)，
      // 用户面前什么都不剩（这正是「窗口一闪、版本没变」的另一条路径）。
      final readyFile = File(
        '${Directory.systemTemp.path}\\liangciyuan-update-$pid.ready',
      );
      if (readyFile.existsSync()) {
        try {
          readyFile.deleteSync();
        } catch (_) {}
      }
      // 安装失败的痕迹：应用重启后由启动检查读出来提示用户，
      // 否则失败后只会「悄悄回到旧版本」，没人知道发生了什么。
      final failedFile = File(
        '${Directory.systemTemp.path}\\liangciyuan-update-$pid.failed',
      );
      if (failedFile.existsSync()) {
        try {
          failedFile.deleteSync();
        } catch (_) {}
      }
      final script = '''
@echo off
chcp 65001 >nul
setlocal
set "APP_NAME=$appName"
set "INSTALLER=${winPath(installerPath)}"
set "APP_EXE=${winPath(appExe.path)}"
set "READY=${winPath(readyFile.path)}"
set "FAILED=${winPath(failedFile.path)}"
rem 先点亮就绪标记，再开始轮询
> "%READY%" echo ready
if not exist "%INSTALLER%" (
  > "%FAILED%" echo installer missing
  goto :relaunch
)
for /l %%i in (1,1,$rounds) do (
  tasklist /fi "IMAGENAME eq %APP_NAME%" /nh 2>nul | find /i "%APP_NAME%" >nul
  if errorlevel 1 goto :gone
  ping -n 2 127.0.0.1 >nul
)
:gone
rem 多等一秒，确保文件句柄（app.so / dll）真的释放
ping -n 2 127.0.0.1 >nul
start "" /wait "%INSTALLER%" $switches
if errorlevel 1 (
  > "%FAILED%" echo installer exit=%ERRORLEVEL%
)
:relaunch
rem 安装结束后重新启动应用（安装被取消时 exe 仍是旧的，也能正常打开）
ping -n 2 127.0.0.1 >nul
if exist "%APP_EXE%" start "" "%APP_EXE%"
endlocal
''';
      // UTF-8 写入（脚本内已 chcp 65001），避免中文路径被按 GBK 解读。
      launcher.writeAsBytesSync(utf8.encode(script), flush: true);
      // `start` 再套一层 cmd：启动器完全脱离本进程，主进程退出后仍继续轮询。
      // 安装包 manifest 要求管理员权限，`start` 走 ShellExecute 会正常触发 UAC。
      Process.start(
        'cmd.exe',
        ['/c', 'start', '""', '/MIN', launcher.path],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      // 等启动器写出就绪标记（最多 3 秒）。拿不到就认为它没起来，
      // 交由调用方回退到可视化安装，而不是让应用直接退出。
      for (var i = 0; i < 30; i++) {
        if (readyFile.existsSync()) return true;
        sleep(const Duration(milliseconds: 100));
      }
      KazumiLogger().w('Update: launcher did not signal ready');
      return false;
    } catch (e) {
      KazumiLogger().w('Update: launch-after-exit failed', error: e);
      return false;
    }
  }

  /// 取走上次安装失败的痕迹（内容为失败原因），没有则返回 null。
  ///
  /// 自动安装是「应用先退出、装完再重启」，失败时用户只会看到
  /// 「应用重新打开还是旧版本」。启动器会写一个 .failed 标记，
  /// 这里在下次启动时读出来提示一次，顺便清掉临时的 .cmd/.ready。
  static String? consumeInstallFailure() {
    if (!Platform.isWindows) return null;
    try {
      final dir = Directory.systemTemp;
      if (!dir.existsSync()) return null;
      String? reason;
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (!name.startsWith('liangciyuan-update-')) continue;
        if (name.endsWith('.failed')) {
          try {
            reason = entity.readAsStringSync().trim();
          } catch (_) {}
          try {
            entity.deleteSync();
          } catch (_) {}
        } else if (name.endsWith('.ready') || name.endsWith('.cmd')) {
          // 启动器已经跑完（有 .failed 说明进程结束过），这些临时文件可以清掉。
          // 没有 .failed 时也清：下次更新会重新生成。
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
      return (reason == null || reason.isEmpty) ? null : reason;
    } catch (e) {
      KazumiLogger().w('Update: consume install failure failed', error: e);
      return null;
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
