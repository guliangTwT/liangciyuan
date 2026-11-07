; 凉次元 Windows 安装包脚本（Inno Setup 6）
; 用法: ISCC.exe /DAppVersion=3.0.0 assets\windows\installer.iss
; 产物: build/windows/x64/runner/Release/liangciyuan-<版本>-windows-x64-setup.exe

#ifndef AppVersion
  #define AppVersion "3.0.0"
#endif

#define MyAppName "凉次元"
#define MyAppNameEn "Liangciyuan"
#define MyAppExeName "liangciyuan.exe"
#define MyAppBuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
; 凉次元在运行时会 mmap data\app.so；让安装器请求 Restart Manager 关闭并重启应用，
; 避免用户忽略“文件被占用”后出现新旧文件混装。
CloseApplications=yes
RestartApplications=yes
; 独立 AppId（GUID），与上游 Kazumi 的安装包互不干扰，可共存。
AppId={{8A6C2F4E-1B3D-4E2A-9C7B-5D4E6F8091A2}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppVerName={#MyAppName} {#AppVersion}
AppPublisher={#MyAppNameEn}
AppPublisherURL=https://github.com/GuLiang-I/liangciyuan
AppSupportURL=https://github.com/GuLiang-I/liangciyuan
; 与 windows/runner/main.cpp 中创建的互斥量一致：安装时提示关闭正在运行的应用。
AppMutex=liangciyuan.win.mutex
DefaultDirName={autopf}\{#MyAppNameEn}
DefaultGroupName={#MyAppName}
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion={#AppVersion}
VersionInfoProductVersion={#AppVersion}
; 版本资源由 Runner.rc 提供（CompanyName/ProductVersion=Liangciyuan），此处仅补安装器元数据
SetupIconFile=..\images\logo\liangciyuan.ico
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog commandline
OutputDir={#MyAppBuildDir}
OutputBaseFilename=liangciyuan-{#AppVersion}-windows-x64-setup
ChangesAssociations=yes
; 应用内更新用 /SILENT /CLOSEAPPLICATIONS /NORESTART 调用本安装包
; （见 lib/services/update/auto_updater.dart），实现无感升级。
; Inno Setup 原生支持静默安装，无需在此额外声明。

[Languages]
; 中文语言文件随仓库分发（runner 预装的 Inno Setup 不含官方翻译）。
Name: "chinesesimplified"; MessagesFile: "InnoLanguages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
    GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#MyAppBuildDir}\*"; DestDir: "{app}"; Excludes: "*-setup.exe"; Flags: ignoreversion restartreplace recursesubdirs createallsubdirs

[Registry]
; URL 协议注册（HKCU 无需管理员权限，卸载时一并删除）。
; liangciyuan:// 为本应用专属；kazumi:// 保留以兼容上游分享链接。
Root: HKCU; Subkey: "Software\Classes\liangciyuan"; ValueType: string; ValueData: "URL:凉次元 Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\liangciyuan"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\liangciyuan\DefaultIcon"; ValueType: string; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCU; Subkey: "Software\Classes\liangciyuan\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\kazumi"; ValueType: string; ValueData: "URL:凉次元 Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\kazumi"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\kazumi\DefaultIcon"; ValueType: string; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCU; Subkey: "Software\Classes\kazumi\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
