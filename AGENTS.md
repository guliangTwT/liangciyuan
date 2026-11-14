# 项目协作约定

## 发布流程（每次更新必须执行完整）

凉次元的正式发布渠道是 **GitHub Releases**：
`https://github.com/guliangTwT/liangciyuan`。
**Codeberg 作为后备**：`https://codeberg.org/GuLiang/liangciyuan`，两处同步维护。
仓库只推 `main` 不会产出安装包；安装包由本机构建，再上传到 Release。
应用内更新先读 GitHub，读不到才退回 Codeberg，不经过任何自建服务器。

每次完成改动后，按顺序执行：

1. **更新 `CHANGELOG.md`**：文件顶部新增 `## <版本号>（YYYY-MM-DD）` 小节，按
   `### 新增` / `### 修复` / `### 变更` 归类，写清用户可感知的变化。
2. **提升 `pubspec.yaml` 的 `version`**：格式 `x.y.z+build`，与 CHANGELOG 一致
   （例如 `1.0.1+10101`）。
3. **验证**：`dart analyze` 不得有 error/warning；`flutter test` 必须全部通过。
4. **构建**（在项目根目录，cmd 里执行）：
   ```bat
   set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
   python tool\fix_ech_http_ca.py .
   flutter build windows
   flutter build apk --release --split-per-abi
   ```
   构建必须在**纯 ASCII 路径**下进行（`subst X: <项目路径>` 后 `cd /d X:\`），
   否则 MSBuild 读 `.dart_tool\flutter_build\*\app.dill` 会报 255。
   - `tool\fix_ech_http_ca.py` 必须在 `flutter pub get` **之后**再跑一次：
     pub 缓存被刷新（换版本、清缓存）会覆盖掉补丁，随后 Windows 构建
     以 `error C2026: 字符串太大` 失败。脚本同时查 `pub.dev` 与
     `pub.flutter-io.cn` 两个缓存目录，镜像环境下也能打上补丁。
   - Windows 安装包用 `assets/windows/installer.iss`：
     `ISCC.exe /DAppVersion=<版本号> /Q assets\windows\installer.iss`
   - 产物按契约命名后放进 `dist\`：
     - `liangciyuan-<版本>-windows-x64-setup.exe`
     - `liangciyuan-<版本>-windows-x64.zip`（可选）
     - `liangciyuan-<版本>-android-arm64.apk`
5. **提交并推送**：`git push origin main`，同时推 Codeberg
   （`git push codeberg main`）。tag 用 `v<版本号>`（`v1.0.0`），应用侧会自动
   去掉 `v` 前缀再比较。
6. **上传发布**：GitHub 用 `github-publish` skill 的脚本，Codeberg 用
   `codeberg-publish` skill 的脚本。两边都要传同一批资产。
7. **验收**：
   ```bat
   dart run tool\verify_update_channel.dart --download
   ```

### 关于 checksums.txt

GitHub 的 release API 自带 `digest`（SHA-256），应用直接用；Codeberg
（Forgejo/Gitea）**不返回摘要**，所以在 Codeberg 发布时必须附带 `checksums.txt`，
应用会读取它把校验值补回资产。缺少校验信息时应用会拒绝下载并跳转发布页，
因此：**Codeberg 侧永远先传安装包，最后传 `checksums.txt`**。

### 发布凭证

- GitHub 与 Codeberg 的 token 都只存在本机 skill 的脚本里，**绝不写进仓库**。
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

## 账号云同步后端（已恢复）

- 代码：`server/liangciyuan-api/`（PHP 8.2 + SQLite，无 Composer 依赖）。
- 线上：`https://guliang.me/liangciyuan/api.php`（虚拟主机 PHP-82，目录 `/liangciyuan`）。
- 部署：`server/liangciyuan-api.zip` 只打包 `api.php`、`lib/`、`config.example.php`、`README.md`，
  用 `hk-vhost` skill 的 `mnbt.ps1 deploy server/liangciyuan-api.zip -To /liangciyuan`。
- 发件配置：服务器 `/liangciyuan/config.local.php` 里的 `mail_user`（QQ 邮箱）与
  `mail_auth`（QQ 授权码），**不提交仓库**。
- 健康检查：`GET /v1/health` 返回 `db` 与 `mailConfigured`。
- **数据目录必须屏蔽直链**：`/data/liangciyuan.sqlite`、`/data/liangciyuan-avatars/`，
  以及 `/liangciyuan/config.local.php`、`/liangciyuan/lib/`、`/liangciyuan/README.md`。
  这些靠面板的伪静态实现，**规则文件只能用 ASCII，注释写中文会被面板按 GBK 解析并吞掉下一行**。
  参考规则：
  ```nginx
  # liangciyuan account API: expose api.php only
  location = /liangciyuan/ { return 403; }
  location = /liangciyuan/config.local.php { return 403; }
  location = /liangciyuan/config.example.php { return 403; }
  location = /liangciyuan/README.md { return 403; }
  location ^~ /liangciyuan/lib/ { return 403; }
  location = /data/liangciyuan.sqlite { return 403; }
  location ^~ /data/liangciyuan-avatars/ { return 403; }
  ```
  改完必须回读验证：`rewrite -Get` 后确认每行都在（中文注释一旦出现就会丢规则）。
- 部署后必查四个状态码：`api.php/v1/ping` 为 200，其余三项为 403。
- 注册仅接受 `@qq.com` / `@vip.qq.com` / `@foxmail.com`。

## 管理后台（/user/）

- 地址：`https://guliang.me/user/`，代码在 `server/admin/`，部署到主机 `/user`。
- 与账号后端**共用同一个 SQLite**（`/data/liangciyuan.sqlite`），不另建库。
- 密码哈希只存在服务器 `/user/config.local.php` 的 `admin_password`，
  用 `password_hash()` 生成；**仓库里不得出现明文或哈希**。
- 能做的事：查看用户列表与详情、观看记录（解析 `p_*` 快照 JSON）、
  收藏同步状态、封禁/解封、删除/恢复评论、删除弹幕。
- 收藏是 Hive 二进制，服务端读不出具体番剧，后台只展示同步状态与体积；
  这是格式限制，不要假装能列出条目。
- 部署前的必查项：
  1. `/user/config.local.php` 与 `/user/lib/` 必须 403（伪静态里已配）；
  2. 未登录访问 `/user/` 应为 302 跳到登录页；
  3. 封禁一个测试账号后，该账号登录与发言都应返回 403。

## 封禁机制

- `users.banned_until`（秒级时间戳，0 为正常）+ `users.ban_reason`；
  两个字段由 `ensure_column` 在首次连库时自动补上，不需要手工迁移。
- 登录时拒绝（403），所有写接口走 `require_writable_user()`；
  读接口仍用 `current_user()`，封禁期间还能看自己的资料。
- 封禁会立刻删除该用户的所有 token，避免旧会话继续生效。