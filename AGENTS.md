# 项目协作约定

## 发布流程（每次更新必须执行完整）

凉次元的唯一发布渠道是 **Codeberg Releases**：`https://codeberg.org/GuLiang/liangciyuan`。
仓库只推 `main` 不会产出安装包；安装包由本机构建，再用 `tool/publish_codeberg.ps1`
上传。应用内更新直接读 Codeberg 的 release API，不经过任何自建服务器。

每次完成改动后，按顺序执行：

1. **更新 `CHANGELOG.md`**：文件顶部新增 `## <版本号>（YYYY-MM-DD）` 小节，按
   `### 新增` / `### 修复` / `### 变更` 归类，写清用户可感知的变化。
2. **提升 `pubspec.yaml` 的 `version`**：格式 `x.y.z+build`，与 CHANGELOG 一致
   （例如 `3.11.0+31100`）。
3. **验证**：`dart analyze` 不得有 error/warning；`flutter test` 必须全部通过。
4. **构建**（在项目根目录，cmd 里执行）：
   ```bat
   set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
   python tool\fix_ech_http_ca.py .
   flutter build windows
   flutter build apk --release --split-per-abi
   ```
   - Windows 安装包用 `assets/windows/installer.iss`：
     `ISCC.exe /DAppVersion=<版本号> /Q assets\windows\installer.iss`
   - 产物按契约命名后放进 `dist\`：
     - `liangciyuan-<版本>-windows-x64-setup.exe`
     - `liangciyuan-<版本>-windows-x64.zip`（可选）
     - `liangciyuan-<版本>-android-arm64.apk`
5. **提交并推送**：
   ```bat
   git add -A
   git commit -m "release: <版本号>"
   git push origin main
   ```
   tag 用裸版本号（`3.11.0`），不要 `v` 前缀；tag 不是发布的前提，发布以 Codeberg
   Release 为准。
6. **上传发布**：
   ```powershell
   $env:CODEBERG_TOKEN = "<token>"
   powershell -ExecutionPolicy Bypass -File tool\publish_codeberg.ps1
   ```
   脚本会：读版本号 → 收集 `dist\` 产物 → 生成 `dist\checksums.txt`（sha256sum 格式）
   → 创建/复用 release → 上传缺失资产 → 最后上传 `checksums.txt` → 回读校验大小。
7. **验收**：
   ```bat
   dart run tool\verify_update_channel.dart --download
   ```
   必须全部通过：tag 是纯数字版本、`checksums.txt` 覆盖每个安装包、每个资产支持
   `Range`、完整下载后 SHA-256 与清单一致。

### 为什么需要 checksums.txt

Codeberg（Forgejo/Gitea）的 release API **不返回资产摘要**，只有文件名、大小和
下载地址。应用会额外拉取同一 release 里的 `checksums.txt`，把 SHA-256 补回资产；
读不到校验文件时应用会拒绝下载并跳转发布页，而不是装一个无法验证的包。
因此：**永远先上传安装包，最后上传 `checksums.txt`**，不要单独补发某一种平台
却不更新校验文件。

### 发布凭证

- `CODEBERG_TOKEN` 只在本地环境变量里，**绝不写进仓库**。需要的权限范围：
  `write:repository`。
- 仓库内不得出现任何 token、keystore 或邮箱授权码。

## Android 发布签名（重要）

- 密钥文件：`android/liangciyuan-release.jks`，已被 `.gitignore` 排除，**绝不入库**。
  仓库外必须保留备份，丢失后无法再覆盖升级，只能让用户卸载重装。
- 密钥别名：`liangciyuan`（4096 位 RSA，有效期至 2126 年）。
- 证书 SHA-256：`AC:EC:CE:98:A5:9C:BE:05:B7:2C:DF:EB:A7:1D:DA:59:8F:1D:6C:A0:E6:D9:36:9C:7C:16:F5:7D:C2:26:48:B1`
- 本地构建从 `android/key.properties` 或同名环境变量读取：
  `ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。
- 发布后核对 APK 签名：
  `apksigner verify --print-certs build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`
  必须是 `CN=Liangciyuan, OU=Release, ...`；若是 `CN=Android Debug`，该包不能作为
  正式发布。
- 更换密钥属于破坏性操作：所有已安装用户都必须卸载重装。非必要不要更换。

## 依赖镜像（默认策略）

- **Maven / Gradle**：`android/settings.gradle` 与 `android/build.gradle` 已把阿里云镜像排在
  官方仓库之前，官方仓库保留为回落；`android/gradle.properties` 配置了下载重试 3 次与
  60 秒超时，避免 Maven Central 429 直接中断构建。
- **Flutter SDK / 引擎**：构建前设置 `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`，
  否则 Gradle 解析 `io.flutter:<abi>_release` 会失败。
- **pub 包**：**不要把 `PUB_HOSTED_URL` 设为默认**。镜像 host 与 `pubspec.lock` 中的
  `https://pub.dev` 不一致，pub 会判定锁定全部失效并全量升级依赖（实测会改写 233 个包）。
  仅在 pub.dev 不可达时临时使用，并接受 lockfile 被刷新：
  `PUB_HOSTED_URL=https://pub.flutter-io.cn flutter pub get`，
  提交前必须检查 `git diff pubspec.lock`。
- 构建若因 Maven 限流失败，直接重跑构建，不要改代码。

## 账号云同步后端（已下线）

- 代码保留在 `server/liangciyuan-api/`（PHP 8.2 + SQLite，无 Composer 依赖）。
- **原线上实例 `https://guliang.me/liangciyuan/api.php` 已随虚拟主机清空而删除**，
  账号注册/登录/云同步当前不可用；Codeberg 不能托管 PHP。
- 若要恢复：把 `server/liangciyuan-api/` 部署到任意支持 PHP 8.2 的主机，然后修改
  `lib/services/storage/settings_keys.dart` 中 `accountApiBase` 的默认值。
- 发件配置：服务器端的 `config.local.php`（QQ 邮箱与授权码）不提交仓库。
- 数据：`liangciyuan.sqlite` 与头像目录，必须放在 Web 根之外或用伪静态禁止直连。
- 注册仅接受 `@qq.com` / `@vip.qq.com` / `@foxmail.com`。