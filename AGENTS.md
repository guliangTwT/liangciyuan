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