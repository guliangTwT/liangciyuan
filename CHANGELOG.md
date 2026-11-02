# 更新日志

所有对凉次元的显著变更都会记录在本文件中。

## 3.0.2（2026-11-03）

### 修复

- **应用内更新的 Windows 安装器无法启动**：安装器清单要求管理员权限，`CreateProcess` 直接启动会得到 ERROR_ELEVATION_REQUIRED（740）。现改经 ShellExecute（`launchUrl`）启动，正常触发 UAC 并弹出安装向导；MSIX 分支合并为同一逻辑。
- CI：为 Windows runner 安装 yq（flutter-action 解析 pubspec 需要）；中文安装界面语言文件随仓库分发（runner 预装的 Inno Setup 不含官方翻译）；安装包排除构建目录中的旧 setup 残留；将编译产物提升到工作区根目录以便 artifact 上传；pubspec 锁定精确的 Flutter 版本供 CI 解析。

## 3.0.1（2026-11-03）

针对发布形态、国内网络访问与上游残留的集中修正。

### 新增

- **Windows 安装包**：新增 Inno Setup 安装器（`liangciyuan-<版本>-windows-x64-setup.exe`），支持开始菜单/桌面快捷方式、`liangciyuan://` 与 `kazumi://` 链接注册、卸载与运行中检测（`AppMutex`）；便携 zip 继续提供。
- **应用内更新支持安装包类型**：更新对话框新增「安装包」类型并作为 Windows 首选，下载完成直接运行安装器；自动匹配 `*windows*x64-setup.exe` 资产并校验 SHA-256。
- **更新下载加速回退**：GitHub 直连失败时自动经 gh-proxy.org 重试 API 查询与资产下载（校验逻辑不变）。

### 修复

- **与上游 Kazumi 共存**：Android `applicationId` 由 `com.predidit.kazumi` 改为 `com.liangciyuan.app`，不再互相覆盖安装；deep link 新增专属 `liangciyuan://` scheme，同时保留 `kazumi://` 兼容上游分享链接；MSIX identity 改为 `GuLiang-I.Liangciyuan`。
- **国内网络访问**：番剧条目/图片默认加速模式由镜像改为 **ECH**——镜像后端已不转发条目详情（404）且搜索接口需要签名（401）；ECH 直连经实测可正常访问条目、封面、搜索与时间表，无需任何配置。
- **虚假信息清理**：README 移除上游 Kazumi 截图与 F-Droid/Flathub/AUR 下载渠道、trendshift/HelloGitHub 徽章、SignPath 签名与赞助段落，下载源只保留本仓库 GitHub Releases 并如实标注签名状态；首次引导移除不存在的「F-Droid 更新来源」选项；删除上游 F-Droid 元数据（fastlane）；CI 中假 publisher（SignPath）改为真实占位。
- **CI 发布流程**：`release.yaml` 重写为真实产物命名（`liangciyuan-<版本>-windows-x64-setup.exe` 等，与应用内更新匹配规则一致）并加入 Inno Setup 打包；`pr.yaml` canary 产物同步改名；移除本仓库无权使用的 SignPath 签名步骤。

### 变更

- Windows 端 exe 名、窗口互斥量、数据目录（`%APPDATA%\Liangciyuan`）此前已与上游区分，本次补充安装器层面的独立 AppId（GUID），两端可长期共存。

### 说明

- Android 端因包名变更视为全新应用，本地数据不会从旧包名迁移。
- 安装包暂未代码签名，Windows 首次运行如遇 SmartScreen 提示，选择「更多信息 → 仍要运行」。
