<div align=center>

<h1>凉次元</h1>

<p>由 [Kazumi](https://github.com/Predidit/Kazumi) 开源项目改编的跨平台番剧探索与播放应用。感谢原作者 Predidit 与所有上游贡献者。本项目继续遵循 GNU GPL-3.0；完整来源与许可证见下方。</p>

<img src="assets/images/logo/liangciyuan.png" width=200></img>

<a href="https://github.com/GuLiang-I/liangciyuan"><img src="https://img.shields.io/badge/GitHub-GuLiang--I%2Fliangciyuan-181717?style=for-the-badge&logo=github&logoColor=white"></img></a>

<img src="https://img.shields.io/badge/Flutter-03A9F4?style=for-the-badge&logo=flutter&logoColor=white"></img>
<img src="https://img.shields.io/badge/Dart-00B4AB?style=for-the-badge&logo=Dart&logoColor=white"></img>

<p>使用 Flutter 开发的基于自定义规则的番剧采集与在线观看程序。使用最多五行基于 <code>Xpath</code> 语法的选择器构建自己的规则。支持规则导入与规则分享。支持基于 <code>Anime4K</code> 的实时超分辨率。绝赞开发中 (～￣▽￣)～</p>
</div>

## 从源码构建

Windows 构建 `ech_http` 的原生桥接时，MSVC 会拒绝其单个超长 CA 字符串。请先运行一次兼容脚本，再执行 Flutter 构建：

```bash
python tool/fix_ech_http_ca.py .
flutter build windows --release
```

Android 产物可直接用 `flutter build apk --release --split-per-abi` 构建。

## 支持平台

本项目目前发布以下平台的安装包：

- Windows 10 及以上（x64，提供 Inno Setup 安装包与便携 zip）
- Android 10 及以上（arm64，APK 分发）

其余平台（macOS / Linux / iOS）的代码继承自上游 Kazumi，可自行从源码构建，本项目暂不提供对应安装包。

> 注：与上游 Kazumi 的包名/数据目录完全独立，可以与官方 Kazumi 共存而不互相覆盖。

## 下载

唯一官方发布渠道是本仓库的 GitHub [Releases](https://github.com/GuLiang-I/liangciyuan/releases/latest) 页面：

<a href="https://github.com/GuLiang-I/liangciyuan/releases">
  <img src="static/svg/get_it_on_github.svg" alt="Get it on Github" width="200"/>
</a>

当前提供的发布资产：

| 平台 | 文件 | 说明 |
| --- | --- | --- |
| Windows | `liangciyuan-<版本>-windows-x64-setup.exe` | 推荐安装方式，支持应用内自动更新 |
| Windows | `liangciyuan-<版本>-windows-x64.zip` | 便携版，解压即用，不含自动更新引导 |
| Android | `liangciyuan-<版本>-android-arm64.apk` | arm64 设备 |

**安装包目前未做代码签名。** Windows 首次运行时若出现 SmartScreen 提示，点击“更多信息 → 仍要运行”即可；该提示仅表示发布者未经证书验证，不代表文件有问题。每个 Release 的资产均附有 SHA-256 校验值（GitHub `digest` 字段），应用内更新会自动校验。

## 屏幕截图

（待补：欢迎提交运行截图）

## 功能 / 开发计划

- [X]  规则编辑器
- [X]  番剧目录
- [X]  番剧搜索
- [X]  番剧时间表
- [X]  番剧字幕
- [X]  分集播放
- [X]  视频播放器
- [X]  多视频源支持
- [X]  规则分享
- [X]  硬件加速
- [X]  高刷适配
- [X]  追番列表
- [X]  番剧弹幕
- [X]  在线更新
- [X]  历史记录
- [X]  倍速播放
- [X]  配色方案
- [X]  跨设备同步
- [X]  无线投屏 (DLNA)
- [X]  外部播放器播放
- [X]  超分辨率
- [X]  一起看
- [X]  番剧下载
- [ ]  番剧更新提醒
- [ ]  还有更多 (/・ω・＼)

## 贡献

欢迎提交 Issue 与 PR。番剧采集规则目前与上游共用 [KazumiRules 规则仓库](https://github.com/Predidit/KazumiRules)（应用内“规则库”默认来源），规则编写教程可参考 [上游规则开发文档](https://kazumi.app/docs/rules/develop-rules)。

## Q&A

<details>
<summary>使用者 Q&A</summary>

#### Q: 为什么少数番剧中有广告？

A: 本项目未插入任何广告。广告来自视频源, 请不要相信广告中的任何内容, 并尽量选择没有广告的视频源观看。

#### Q: 为什么我启用超分辨率功能后播放卡顿？

A: 超分辨率功能对 GPU 性能要求较高, 如果没有在高性能独立显卡上运行, 尽量选择效率档而非质量档。对低分辨率视频源而非高分辨率视频源使用超分也可以降低性能消耗。

#### Q: 为什么播放视频时内存占用较高？

A: 本程序在视频播放时, 会尽可能多地缓存视频到内存, 以提供较好的观看体验。如果您的内存较为紧张, 可以在播放设置选项卡启用低内存模式, 这将限制缓存。

#### Q: 为什么少数番剧无法通过外部播放器观看？

A: 部分视频源的番剧使用了反盗链措施, 这可以被本应用解决, 但无法被外部播放器解决。

#### Q: 为什么下载的 Windows 便携版缺少图标和托盘功能？

A: 使用 setup.exe 安装包进行安装, zip 便携版仅为免安装场景准备, 这一格式先天缺乏快捷方式与卸载支持。

</details>

<details>
<summary>规则编写者 Q&A</summary>

#### Q: 为什么我的自定义规则无法实现检索？

A: 目前我们对 `Xpath` 语法的支持并不完整, 我们目前只支持以 `//` 开头的选择器。建议参照我们给出的示例规则构建自定义规则。

#### Q: 为什么我的自定义规则可以实现检索, 但不能实现观看？

A: 尝试关闭自定义规则的使用内置播放器选项, 这将尝试使用 `webview` 进行播放, 提高兼容性。但在内置播放器可用时, 建议启用内置播放器, 以获得更加流畅并带有弹幕的观看体验。

</details>

<details>
<summary>开发者 Q&A</summary>

#### Q: 我在尝试自行编译该项目, 但编译没有成功。

A: 本项目编译需要良好的网络环境, 除了由 Google 托管的 Flutter 相关依赖外, 本项目同样依赖托管在 MavenCentral/Github/SourceForge 上的资源。如果您位于中国大陆, 可能需要设置恰当的镜像地址；Windows 构建前请先运行 `python tool/fix_ech_http_ca.py .`。

</details>

## 美术资源

本项目图标由凉次元改编版使用，源自用户提供的“凉次元梦幻星轨头像.png”。

本项目内嵌字体为 [Mi Sans](https://hyperos.mi.com/font/zh/details/sc/) 字体, 由 [Xiaomi](https://www.mi.com/index.html) 开发和拥有版权。

## 免责声明

本项目基于 GNU 通用公共许可证第 3 版（GPL-3.0）授权。我们不对其适用性、可靠性或准确性作出任何明示或暗示的保证。在法律允许的最大范围内, 作者和贡献者不承担任何因使用本软件而产生的直接、间接、偶然、特殊或后果性的损害赔偿责任。

使用本项目需遵守所在地法律法规, 不得进行任何侵犯第三方知识产权的行为。因使用本项目而产生的数据和缓存应在24小时内清除, 超出 24 小时的使用需获得相关权利人的授权。

## 隐私政策

我们不收集任何用户数据, 不使用任何遥测组件。

## 改编来源与许可证

凉次元改编自 [Kazumi](https://github.com/Predidit/Kazumi)，感谢原作者 Predidit 及所有上游贡献者。本项目基于 GNU GPL-3.0 发布，保留原始 [LICENSE](LICENSE) 与上游代码中的版权声明。分发修改版时请同时提供对应源代码并遵守 GPL-3.0。

原 Kazumi 图标由 Yuquanaaa 创作并拥有版权，授权仅适用于原项目。本改编版不再使用该图标，当前应用图标为用户提供的凉次元素材。

## 致谢

特别感谢 [XpathSelector](https://github.com/simonkimi/xpath_selector) 这个优秀的项目是本项目的基石。

特别感谢 [弹弹play](https://www.dandanplay.com/) 本项目使用了 弹弹play开放平台 以提供弹幕交互。

特别感谢 [Bangumi](https://bangumi.tv/) 本项目使用了 Bangumi 开放 API 以提供番剧元数据。

特别感谢 [Anime4K](https://github.com/bloc97/Anime4K) 本项目使用 Anime4K 进行实时超分。

特别感谢 [SyncPlay](https://github.com/Syncplay/syncplay) 本项目使用 SyncPlay 协议并通过 SyncPlay 公共服务器实现一起看功能。

特别感谢 [所有上游贡献者](https://github.com/Predidit/Kazumi/graphs/contributors) 本项目因为你们变得更好。

特别感谢 [trace.moe](https://trace.moe) 本项目使用了 trace.moe 提供的图片识别番剧功能。

感谢 [media-kit](https://github.com/media-kit/media-kit) 本项目跨平台媒体播放能力来自 media-kit。

感谢 [avbuild](https://github.com/wang-bin/avbuild) 本项目使用了来自 avbuild 的树外补丁实现非标准视频流播放。

感谢 [hive](https://github.com/isar/hive) 本项目持久化储存能力来自 hive。
