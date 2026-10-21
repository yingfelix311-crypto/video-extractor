<p align="center"><img src="docs/images/social-preview.png" alt="Video Extractor：把喜欢的片段，带回来。" width="100%"></p>

# Video Extractor 1.4.1

原生 macOS 视频与音频工具：粘贴视频链接或整段分享文字，提取视频 / MP3，保存后可打开、定位或截取片段。支持菜单栏快捷输入、独立任务记录、按需读取浏览器网站会话与空闲时更新下载引擎。

**[下载 macOS 安装包（ZIP）](https://github.com/yingfelix311-crypto/video-extractor/releases/download/native-v1.4.1/Video-Extractor-Native-1.4.1-macOS-arm64.zip)** · [版本说明](https://github.com/yingfelix311-crypto/video-extractor/releases/tag/native-v1.4.1) · [完整安装说明](docs/INSTALL-MAC.md) · [操作与开发说明](Shouxia/README.md) · [依赖与授权](distribution/macos/licenses/DEPENDENCIES.md)

仓库和安装包已公开，无需申请仓库访问权限。支持 **Apple Silicon（M 系列）、macOS 14+**。`desktop/` 是单独的 Electron 实验客户端，与这里发布的原生版功能不一致；本次发布只包含原生 Mac 版，不发布 Windows 安装包。

## 40 秒实机流程

[![播放 Video Extractor 实机演示](docs/images/demo-poster.jpg)](docs/marketing/video-extractor-walkthrough.mp4)

[播放 / 下载 MP4](docs/marketing/video-extractor-walkthrough.mp4) · [文字字幕与录制范围](docs/marketing/TRANSCRIPT.md)

实机操作录像，展示链接提交、真实下载、视频播放、21:9 画布、2–8 秒片段预览及成功导出；结尾播放本次导出文件的节选。使用自制素材，无声字幕，经过取景放大与剪辑。

## English overview

Video Extractor is a native **macOS video and audio downloader** built with SwiftUI, AVFoundation and yt-dlp through a local MeTube service. Paste a video link or share text, save video or MP3, then trim a clip with a standard or custom aspect ratio. Quality options include 1440p / 2160p when the source provides them.

The current prerelease supports **Apple Silicon and macOS 14+**. Download the ZIP above, extract the complete folder and run `安装原版.command`; the installer prepares the runtime and local backend. Internet is required on first installation. The app is ad-hoc signed and not Apple-notarized. See the [installation guide](docs/INSTALL-MAC.md) for setup and limitations.

## 安装后怎么用

1. 从下载页获取 `Video-Extractor-Native-1.4.1-macOS-arm64.zip`，完整解压。
2. 双击文件夹中的 `安装原版.command`。首次联网自动准备运行组件与下载服务，通过检查后安装并打开 App。无需另装 Homebrew、Docker Desktop、Python、Node 或 FFmpeg。
3. 粘贴链接，确认保存文件夹，点击 **提取**。默认最佳画质，浏览器会话辅助默认关闭。

安装器包含 Colima、Docker CLI、Lima；首次仍需联网下载 Linux 基础镜像和固定 MeTube 镜像 / 下载引擎，可能需要数分钟。后台配置为 2 CPU、2 GiB 内存、20 GiB 虚拟磁盘容量。初次联网初始化是安装过程的一部分，安装完成后即可提交下载。

这是 **ad-hoc 签名的测试发行版，未获 Apple 公证**。macOS 可能要求用户在“隐私与安全性”中确认信任；不要关闭系统保护。正式面向任意用户无障碍分发仍需 Developer ID 签名、公证及干净 Mac 的完整安装验收。运行环境冲突时安装器会停止并说明原因，不覆盖其他工具。

## 功能

| 功能 | 行为 |
| --- | --- |
| 视频 / MP3 | 支持单视频链接、分享文字、拖入链接，提供进度、取消、重试与保存恢复 |
| 画质 | 最佳、4K（2160p）、2K（1440p）、1080p、720p、480p；选择源站可用且不超过上限的格式，不放大成假高清 |
| 保存与记录 | 任务保留提交时的文件夹；同一链接分别提取视频和音频，分别保留记录；移除记录保留文件 |
| 快捷输入 | 菜单栏入口和主窗口的“快捷输入”，带清空操作和查看任务入口 |
| 网站访问辅助 | 可选指定浏览器 / 配置；仅读取该平台的 Cookie；默认关闭，手动导入位于高级设置 |
| 设置与错误 | 统一保存入口；简短失败原因；后台健康概览与按需展开的详细信息 |
| 本地截取 | 开始 / 结束时间线、0.25–2× 倍速、原视频比例、16:9 / 21:9 / 4:3 等常用比例、自定义比例或像素宽高、可缩放预览和新文件导出 |
| 下载引擎 | 空闲时检查 / 更新 yt-dlp；本次安装包含抖音移动分享页解析补充插件 |

4K / 2K 是否存在由视频源决定。部分网站需要分离的视频、音频轨合并，安装器准备 FFmpeg 完成这一步。选择兼容 MP4 会限制可选源格式，可能获得更低清晰度；它不是转码开关。

## 剪辑画面比例

在剪辑窗口的“画面比例”中选择原视频比例、16:9、21:9、4:3、3:2、1:1、9:16、3:4、2:3、4:5 或自定义。21:9 使用2520×1080；比例和实际像素分开显示。

“自定义”支持按比例（如5:4、2.35:1）和按像素（如1280×1024）两种方式，输入后即时更新预览。比例模式按1080像素短边推算并取偶数像素；像素模式可精确输入64–8192之间的偶数宽高，总像素有上限。无效输入会提示原因并阻止导出。预览和导出使用同一画布，完整显示并补黑边；预览缩放仅改变屏幕上的显示大小。

## Cookie 和浏览器：什么时候设置

先直接下载。能下载就不必开启任何浏览器设置。只有网站明确要求登录，或需要尝试已有网站会话时，打开 **设置 → 网站访问辅助**，开启后选择平时使用的浏览器及用户配置，点击 **保存并关闭**，再重试。

- 复制链接的浏览器和系统默认浏览器不决定会话来源；以软件中保存的选择为准。
- Chrome / Edge 可能请求钥匙串授权；Safari 实际读取被拒绝时才需要为当前 App 开启完全磁盘访问权限并重启 App。
- Cookie 可以只是访客会话。读取成功不能证明账号已登录，也不能保证网站接受请求。
- 不扫描其他浏览器，不读取密码或历史。会话在本机处理，由本机服务发送给对应网站，不上传开发者服务器。临时文件在后台确认任务结束后清理；不确定的任务保留到核对完毕。
- “本次不读取浏览器”只跳过这一次自动读取；此前手动导入的 Cookie 仍独立存在，可在高级设置删除。

## 平台验证范围（2026-10-18）

这是实际有限样例，不是对整个平台的承诺。Safari 与 Chrome 均按保存的具体配置验证，未把“有 Cookie”当作“已登录”。

| 平台 | 不导入浏览器 Cookie 的样例 | Chrome / Safari 样例观察 |
| --- | --- | --- |
| YouTube | 成功 | Chrome 有站点 Cookie 也成功；Safari 无站点 Cookie 仍成功 |
| Bilibili | 成功 | 两个浏览器会话样例均成功 |
| TikTok / Instagram / X | 成功 | Chrome 会话样例成功；Safari 无站点 Cookie 仍成功 |
| 小红书 | 有效完整分享链接成功 | Safari 会话样例成功；Chrome 无站点 Cookie 也成功。旧失效样例加入 Cookie 仍失败 |
| 抖音 | 当前样例直接解析失败 | 所测 Chrome、Safari 会话配合本项目分享页插件成功；不据此推断必须登录或全部视频都需要 Cookie |
| 快手 | 当前解析器不支持 | 加 Cookie 无法补足缺失的解析器，暂不列为支持平台 |

部分网页自身会创建访客 Cookie，这与从用户浏览器导入 Cookie 是两回事。失效链接、源站没有视频格式、网络限制和站点解析器失效，也不能统一归因于 Cookie。

## 数据、运行与卸载

文件默认缓存在 `~/Downloads/MeTube`，再保存到任务选择的文件夹；偏好及本地记录在当前用户下保存。关闭窗口后可通过菜单栏继续操作；退出 App 不会终止后台已提交的下载。安装器不创建频道订阅，不带作者的浏览器数据、历史、媒体或虚拟机磁盘。

只卸载客户端：退出后把 `~/Applications/Video Extractor.app` 移入废纸篓。用户媒体不会随卸载删除。停止后台资源使用见 [安装说明](docs/INSTALL-MAC.md#检查停止与卸载)。

## 开发与验证

开发依赖：Apple Silicon Mac、macOS 14+、Xcode Command Line Tools（Swift 编译器）、Python 3.11+（打包脚本使用 `hashlib.file_digest`）、Git。Python 只供维护者打包和运行测试，最终用户无需安装。

```sh
bash Shouxia/test.sh
bash Shouxia/test-store.sh
bash Shouxia/test-completion.sh
bash Shouxia/test-settings.sh
bash Shouxia/test-submissions.sh
bash Shouxia/test-backend.sh
bash Shouxia/test-runtime.sh
bash Shouxia/test-browser-cookies.sh
bash Shouxia/test-browser-session.sh
bash Shouxia/test-update.sh
bash Shouxia/build.sh
python3 -m unittest discover -s distribution/tests -p 'test_*.py'
```

应用输出到 `Shouxia/build/Video Extractor.app`。打包和可选剪辑测试命令见 [开发说明](Shouxia/README.md)。本次仅针对新改动验证画面比例、自定义尺寸和对应短片导出，没有重复全部剪辑功能回归，详见 [1.4.1 验证记录](docs/VALIDATION-1.4.1.md)。安装器已覆盖校验、冲突保护、恢复和已有环境复用测试；不把这些测试等同于一台干净 Mac 的首次安装验收。

## 反馈与参与

遇到问题可提交 [Bug 反馈或功能建议](https://github.com/yingfelix311-crypto/video-extractor/issues/new/choose)，表单会引导填写版本、步骤和结果。只提供可公开的样例链接；不要上传 Cookie、密码、浏览器数据库或带有个人信息的日志。

维护者可查看 [Mac 正式签名、公证与干净安装验收流程](docs/RELEASE-MAC.md)。项目分享素材与中英文介绍在 [推广素材包](docs/marketing/SHARE-COPY.md)。

第三方依赖遵循各自许可证，见 [依赖与授权](distribution/macos/licenses/DEPENDENCIES.md)。仓库公开与源码开源许可是两回事；当前尚未为自有源码选择许可证。

## 安装可靠性改进（1.4.2 候选版，尚未替换上方 1.4.1 公开附件）

新打包流程将完整后台安装组件放进唯一的 App：复制应用后首次打开自动准备 MeTube，显示当前步骤，中断可重试。补齐 Colima 必需的 `lima` 命令，只有服务、下载引擎和解析插件检查通过才允许提取。详见 [改动与验证门槛](docs/FIRST-LAUNCH-1.4.2.md)。重新发布候选包前，上方旧版下载入口仍采用旧的安装方式。
