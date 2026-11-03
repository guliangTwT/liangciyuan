# 更新日志

所有对凉次元的显著变更都会记录在本文件中。

## 3.0.7（2026-11-03）

### 变更

- **追番同步不再需要绑定 Bangumi**：追番列表（收藏）本就支持通过 WebDAV 在设备间同步，且与 Bangumi 完全独立；此前界面把它笼统写作「收藏」，容易让人误以为必须连接 Bangumi。现在同步设置里明确标为「追番（收藏）」并注明「无需绑定 Bangumi」，总页的 WebDAV 卡片也标注了「无需 Bangumi 账号」，能力清单改为「追番 · 观看记录 · 收藏 · 弹幕屏蔽词」。
- 只启用 WebDAV 时，追番页的同步流程只执行 WebDAV 合并，不会出现 Bangumi 步骤；只有同时开启 Bangumi 同步时才会多出该步骤。

### 说明

- WebDAV 同步内容：追番（收藏）、观看记录与播放进度、弹幕屏蔽词；只需云盘地址与账号密码（如坚果云、Nextcloud）。
- Bangumi 同步仍然保留，用于与其他使用 Bangumi 的客户端互通追番状态（需要授权码）。

## 3.0.6（2026-11-03）

### 修复

- **CI 即使配置密钥也会构建失败**：`build.gradle` 中的 `file('liangciyuan-release.jks')` 解析为 `android/app/`，而工作流把密钥写到 `android/`，路径不一致导致读不到密钥。现统一改为 `rootProject.file(...)`，与密钥存放位置一致。
- **缺少签名密钥时 CI 直接失败**：`Verify keystore present` 步骤在未配置 secret 时中断整个发布。现改为输出 warning 并跳过，退回调试签名继续产出可安装包，避免发布流水线被密钥配置阻塞。
- **Release 说明乱码**：发布脚本调用 GitHub API 时，PowerShell 5 以 ISO-8859-1 发送字符串，中文全部变成 `?`。现改为显式以 UTF-8 字节提交。

### 变更

- Android 发布签名统一走 `android/liangciyuan-release.jks`；口令通过 `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD` 覆盖，本地构建使用内置默认值。
- CI 增加签名证书输出步骤，便于核对每次发布的证书是否一致。

### 验证

- MuMu 模拟器（Android 15 / x86_64）实测：同签名 APK 覆盖安装返回 `Success`，应用冷启动后首页直接渲染推荐列表，无需滑动。

### 包含的先前修复

本版本合并了 3.0.4 / 3.0.5 尚未在 Release 中提供的改动：

- 修复首页推荐列表首屏空白（数据到达后不重建，需滑动才显示）。
- 更换应用图标（Android / iOS / macOS / Windows / 安装器全套资源）。
- Android 发布签名由调试密钥改为固定发布密钥，解决覆盖安装的签名冲突。

## 3.0.5（2026-11-03）

### 修复

- **Android 覆盖安装报签名冲突**：release 构建此前沿用 `signingConfigs.debug`，调试密钥由每台构建机（含每个 CI runner）随机生成，因此每次发布的签名都不同，覆盖安装必然报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。现改用固定发布密钥（`android/liangciyuan-release.jks`，CI 由 secrets 注入），证书主体为 `CN=Liangciyuan`，同一证书签名的后续版本可正常覆盖安装。已在 MuMu 模拟器实测：旧调试签名包覆盖新包失败、新签名包覆盖成功。
- **首页推荐列表首屏空白（真正的根因）**：`Observer` 只追踪 builder 内同步读取的 Observable，而列表读取发生在 `SliverLayoutBuilder.builder`（布局阶段，不参与依赖追踪），数据到达后不会触发重建，表现为首屏空白、滚动后才出现。现于 `Observer` 内同步取值后再构建网格；3.0.4 加入的骨架占位继续保留，加载中亦有明确反馈。已在模拟器实测：冷启动直接显示番剧列表，无需滑动。

### 说明

- 本次更换了 Android 签名证书，**从旧版本升级需要先卸载旧版**（仅此一次）；从 3.0.5 起的后续版本可正常覆盖安装，本地数据不会再丢失。

## 3.0.4（2026-11-03）

### 修复

- **首页首屏空白，滑动后才出现番剧**：推荐列表首次加载时，网格用 `null` 子项占位（此前 `childCount` 固定为 10 但内容为空），Sliver 懒加载下整屏空白。现改为渲染与真实卡片同尺寸的骨架占位，加载完成即替换。

### 变更

- **更换应用图标**：启用新的凉次元图标（黑发少女 + 黑猫 + 播放窗口 + 粉色星轨），已重新生成 Android 自适应图标 / iOS / Windows / macOS 全套资源与安装器图标。

## 3.0.3（2026-11-03）

### 修复

- **覆盖安装后仍显示旧版本、功能不生效**：应用运行时映射了 `data\app.so`，旧安装器遇到被占用的文件只能由用户“忽略”，造成新旧文件混装（注册表已是新版、程序仍是旧代码）。安装器现启用 CloseApplications / RestartApplications / restartreplace：安装前请求关闭正在运行的凉次元，并在安装完成后自动重启。
- 同步设置补充说明：WebDAV 只需云盘账号密码即可同步**观看记录、收藏与弹幕屏蔽词**；Bangumi 仅同步追番状态（想看 / 在看 / 看过等），且 Bangumi 官方不提供账号密码登录，需要授权码；官网打不开时可在其他设备获取授权码后粘贴。

### 说明

- 如果当前安装目录出现“版本号与功能不一致”（例如关于页仍显示 3.0.0），请退出凉次元后重新运行本安装包覆盖安装一次。

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
