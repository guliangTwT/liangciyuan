# 项目协作约定

## 发布流程（每次更新必须执行完整）

凉次元的成品通过 GitHub Releases 分发，**只推 `main` 分支不会产出可下载的安装包**。
每次完成改动后，必须按顺序执行：

1. **更新 `CHANGELOG.md`**：在文件顶部新增 `## <版本号>（YYYY-MM-DD）` 小节，按
   `### 新增` / `### 修复` / `### 变更` 归类，写清用户可感知的变化。
2. **提升 `pubspec.yaml` 的 `version`**：格式 `x.y.z+build`，与 CHANGELOG 版本号一致
   （例如 `3.0.8+30008`）。
3. **验证**：`dart analyze` 不得有 error/warning；`flutter test` 必须全部通过。
4. **提交并推送**：`git push origin main`。
5. **打 tag 并推送**：`git tag <版本号> && git push origin <版本号>`。
   - tag 必须是裸版本号（`3.0.8`），不要加 `v` 前缀；
   - 使用轻量 tag，与既有 `3.0.1` ~ `3.0.7` 保持一致；
   - tag 指向包含全部改动的 `main` 提交。
6. **确认发布**：`gh run list` 查看 `release` 工作流，等待
   `flutter-analyze → flutter-test → android → windows → release` 全部成功，
   并确认 Release 中包含 `.apk`、`.exe`、`.zip` 三类产物。

### 说明

- `.github/workflows/release.yaml` 由 **tag 推送**触发（`on: push: tags: "*"`），
  普通分支推送不会构建。
- Release 说明由工作流自动从 `CHANGELOG.md` 提取同名 `## <tag>` 小节；
  因此 CHANGELOG 的标题必须与 tag 完全一致，否则说明会退化为默认提示。
- 不要用 `gh release create` 手工补发，统一走 tag 触发，保证渠道一致。

## Android 发布签名（重要）

- 密钥文件：`android/liangciyuan-release.jks`，已被 `.gitignore` 排除，**绝不入库**。
  仓库外必须保留备份，丢失后无法再覆盖升级，只能让用户卸载重装。
- 密钥别名：`liangciyuan`（4096 位 RSA，有效期至 2126 年）。
- 证书 SHA-256：`AC:EC:CE:98:A5:9C:BE:05:B7:2C:DF:EB:A7:1D:DA:59:8F:1D:6C:A0:E6:D9:36:9C:7C:16:F5:7D:C2:26:48:B1`
- CI 通过以下仓库 Secrets 读取，缺任意一个都会退回调试签名并打警告：
  - `ANDROID_KEYSTORE_BASE64`：`base64 -w0 android/liangciyuan-release.jks`
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`
- 发布后必须确认 Android 作业日志里是
  `certificate DN: CN=Liangciyuan, OU=Release, ...`；若是 `CN=Android Debug`
  说明密钥未生效，该包不能作为正式发布。
- 更换密钥属于破坏性操作：所有已安装用户都必须卸载重装。非必要不要更换。

## 依赖镜像（默认策略）

- **Maven / Gradle**：`android/settings.gradle` 与 `android/build.gradle` 已把阿里云镜像排在
  官方仓库之前，官方仓库保留为回落；`android/gradle.properties` 配置了下载重试 3 次与
  60 秒超时，避免 Maven Central 429 直接中断构建。
- **Flutter SDK / 引擎**：CI 默认设置 `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`；
  本机已持久化同名用户环境变量。
- **pub 包**：**不要把 `PUB_HOSTED_URL` 设为默认**。镜像 host 与 `pubspec.lock` 中的
  `https://pub.dev` 不一致，pub 会判定锁定全部失效并全量升级依赖（实测会改写 233 个包）。
  仅在 pub.dev 不可达时临时使用，并接受 lockfile 被刷新：
  `PUB_HOSTED_URL=https://pub.flutter-io.cn flutter pub get`，
  提交前必须检查 `git diff pubspec.lock`。
- Release 构建若因 Maven 限流失败，直接 `gh run rerun <run-id> --failed` 重试，不要改代码。## 账号云同步后端（自建）

- 代码：`server/liangciyuan-api/`（PHP 8.2 + SQLite，无 Composer 依赖）。
- 线上：`https://guliang.me/liangciyuan/api.php`（虚拟主机 PHP-82）。
- 部署：`mnbt.ps1 deploy server/liangciyuan-api.zip -To /liangciyuan`，zip 只打包 api.php、lib/、config.example.php、README.md。
- 发件配置：服务器 `/liangciyuan/config.local.php` 中的 `mail_user`（QQ 邮箱）与 `mail_auth`（QQ 授权码），不提交仓库。
- 健康检查：`GET /v1/health` 返回 `db` 与 `mailConfigured`。
- 数据：`/data/liangciyuan.sqlite` 与 `/data/liangciyuan-avatars/`，根站伪静态已禁止直接访问。
- 注册仅接受 `@qq.com` / `@vip.qq.com` / `@foxmail.com`。
