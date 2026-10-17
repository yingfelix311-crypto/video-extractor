<p align="center">
  <img src="docs/images/cover.svg" alt="Video Extractor：把喜欢的片段，带回来。下载视频与音频、拖动截取、按倍速导出。" width="100%">
</p>

<p align="center">
  <strong>从一个链接，到一段值得留下的视频。</strong><br>
  为 macOS 制作的原生影音工具：下载、预览、截取，在一个应用中完成。
</p>

<p align="center">
  <a href="#功能">功能</a> ·
  <a href="#开始使用">开始使用</a> ·
  <a href="#构建与验证">构建与验证</a> ·
  <a href="Shouxia/README.md">详细说明</a>
</p>

## macOS / Windows 独立安装版（测试版）

新增 `desktop/` 独立客户端，安装包内置下载与剪辑引擎，无需配置 Docker、Python 或 MeTube。支持视频 / MP3 下载、双节点片段选择、0.25–2× 自定义倍速预览和导出。保留深色、紫色与黄绿色设计。

- **Mac**：macOS 14 及以上，Apple Silicon（M1 / M2 / M3 / M4）。
- **Windows**：Windows 10 / 11，x64。
- 当前为尚未公证、没有开发者证书的测试包，系统可能限制首次启动。构建产物位于 GitHub Actions，尚未发布公开 Release。
- [安装与构建说明](desktop/README.md) · [安装包构建记录](https://github.com/yingfelix311-crypto/video-extractor/actions/workflows/build-installers.yml)

以下介绍包含原 SwiftUI 客户端功能；菜单栏入口、快捷输入框、引擎自动升级及 1.2.0 浏览器 Cookie 自动同步目前仅在原客户端提供。

## 功能

| 从这里开始 | 你可以做什么 |
| :--- | :--- |
| **粘贴链接，带回视频** | 提取视频或 MP3 音频，选择画质，查看真实下载进度。 |
| **拖动两端，留下片段** | 打开已下载或本地视频，拖动时间线的开始、结束节点；高亮区域就是导出范围。 |
| **按自己的节奏播放** | 播放／暂停一键切换，支持常用倍速及 **0.25–2×** 自定义倍速。 |
| **预览确认，变速导出** | 导出采用点击导出时的倍速，画面与音频同步变速，保存为新的 MP4，保留原文件。 |
| **文件放在顺手的地方** | 自选保存目录、打开文件、在 Finder 中定位；保存失败可更换位置并重试。 |
| **需要时，随手打开** | 菜单栏粽子入口与 Spotlight 风格快捷输入框；下载引擎在空闲时自动检查更新。 |

深色底、紫色标识、黄绿色操作按钮，搭配 Sora / Manrope 字体。界面保持统一，让操作集中在视频本身。

### 片段截取

![实际时间线组件：开始与结束节点之间的高亮区域为导出片段，白线表示播放位置](docs/images/clip-timeline.png)

*实际组件渲染示例：双节点选择范围，白线显示当前播放位置。*

1. 点击已完成视频旁的 **剪刀**，或选择 **文件 → 截取本地视频…**（`⇧⌘K`）。
2. 拖动开始、结束节点选择范围；也可输入时间，精确到毫秒。
3. 选择播放倍速，点击 **预览片段** 核对。
4. 点击 **导出片段**，选择保存位置。

**例如：** 选中原视频的 10 秒，选择 `2×`，导出约为 5 秒；选择 `0.5×`，导出约为 20 秒。界面会显示预计导出时长。每次导出一个片段，支持取消，已有同名文件不会被覆盖。

## 开始使用

### 环境要求

- **Apple Silicon Mac · macOS 14+**。
- Apple Command Line Tools，用于本地构建。
- 下载功能依赖已经配置好的 **Colima / Docker / MeTube**：`metube` profile、`metube` 容器、`127.0.0.1:8081`，并挂载 `~/Downloads/MeTube` 到 `/downloads`。
- 本地片段处理使用系统 **AVFoundation**，无需 AI 模型或上传视频。

> 当前仓库提供原生客户端源码与本机构建脚本，尚未提供自动配置下载后端的通用安装包。片段导出消耗随视频分辨率和片段长度增加。

### 下载视频或音频

打开应用 → 粘贴链接 → 选择视频／音频与画质 → 点击 **提取**。

可从分享文字中识别链接，也可拖入链接。新任务会记住所选保存位置；保存失败时，界面显示错误原因，并支持选择其他文件夹后重试。

### 平台范围

解析能力由本机 MeTube / yt-dlp 提供，是否可用取决于具体链接、网络、登录要求及平台变化。

| 2026-10-01 样例验证 | 结果 |
| :--- | :--- |
| YouTube · Bilibili · TikTok · X | 所测样例下载成功 |
| Instagram | 所测样例未提供可下载视频格式 |
| 抖音 | 所测样例要求 Cookie |

以上是有限样例结果，不代表整个平台的所有链接都能下载。SwiftUI 客户端支持手动导入 Cookie，并可选择浏览器配置后自动同步对应平台的 Cookie。

### 自动复用浏览器登录状态（SwiftUI 1.2.0）

打开 **下载设置 → 浏览器登录状态**，开启自动同步，选择 Chrome、Edge、Firefox 的标准本机配置或 Safari 默认存储，点击 **保存浏览器 Cookie 设置**。默认关闭；浏览器和用户配置的修改在保存后生效。首次启用需要后台空闲，可能配置并重启本机下载服务。

之后每次提交或重试抖音、YouTube、Bilibili、TikTok、Instagram、X、小红书、快手链接时，只读取所选配置中对应平台的 Cookie。短链按已知平台域名映射；不会为任意网页扫描全部登录状态。Chrome / Edge 可能请求 macOS 钥匙串授权，Safari 可能需要 **隐私与安全性 → 完全磁盘访问权限**；设置中提供浏览器、刷新配置和系统权限入口。Firefox 不读取容器或分区会话。

Cookie 仅在本机处理，不读取密码、历史记录或云端浏览器数据。每个请求使用独立私有会话文件，通过已验证的本机 MeTube 挂载目录提供给下载引擎；后台确认结束后清理，未决任务保留文件以便核对。关闭自动同步会停止后续读取，闲置文件可在设置中清理。手动 Netscape 文件导入（最多 1 MB）和删除仍单独保留。

同步成功不代表已登录或有下载权限。登录过期时，在浏览器中切换到所选配置重新登录，再重试以读取最新 Cookie；权限或加密不兼容时可关闭自动同步并手动导入。自动同步不会绕过网站验证、付费访问、地区限制或 DRM；没有可用站点 Cookie 时尝试公开访问。开发验证使用合成样本，不提取真实账户 Cookie。

## 记录、文件与后台

- **移除记录**只清理任务历史，保留已下载文件。
- 截取会生成新的 MP4，原视频保持不变。
- 退出客户端不会停止 MeTube 后台；其他入口提交的任务也会显示在列表里。
- 客户端**不会创建自动视频订阅**。如果已有 MeTube 后台配置了频道或播放列表订阅，它仍可独立产生下载任务，需要在后台管理。
- 下载缓存、订阅配置、账户凭据及运行日志不属于项目源码，不应提交到仓库。

## 构建与验证

```sh
# 在仓库根目录执行；以下测试不提交下载任务
bash Shouxia/test.sh
bash Shouxia/test-store.sh
bash Shouxia/test-backend.sh
bash Shouxia/test-runtime.sh
bash Shouxia/test-submissions.sh
bash Shouxia/test-browser-cookies.sh
bash Shouxia/test-browser-session.sh
bash Shouxia/test-clips.sh
bash Shouxia/test-clip-timeline.sh
bash Shouxia/test-update.sh

# 构建原生应用
bash Shouxia/build.sh

# 退出正在运行的应用后安装
bash Shouxia/install.sh
```

安装位置：`~/Applications/Video Extractor.app`。采用本机 ad-hoc 签名，未进行 Apple 公证。

如需验证实际导出，可向 `test-clips.sh` 传入一个**带音轨、时长超过 2.75 秒的本地短视频**：

```sh
bash Shouxia/test-clips.sh "/path/to/sample.mp4"
```

测试截取 1.5 秒范围，校验正常导出、0.5× / 1.35× / 2× 变速时长、音轨时长、取消清理和防覆盖；临时输出会自动清理。

## 代码导航

| 模块 | 位置 |
| :--- | :--- |
| 主窗口与快捷输入 | [MainView.swift](Shouxia/Sources/MainView.swift) |
| 截取窗口、双节点时间线与倍速控件 | [ClipEditor.swift](Shouxia/Sources/ClipEditor.swift) |
| 时间校验、音视频变速与导出 | [ClipExporter.swift](Shouxia/Sources/ClipExporter.swift) |
| 任务状态与保存流程 | [Store.swift](Shouxia/Sources/Store.swift) · [Destination.swift](Shouxia/Sources/Destination.swift) |
| 后台连接与引擎维护 | [Backend.swift](Shouxia/Sources/Backend.swift) · [EngineUpdater.swift](Shouxia/Sources/EngineUpdater.swift) |
| 配色、字体与按钮 | [Theme.swift](Shouxia/Sources/Theme.swift) |

详细操作见 [使用说明](Shouxia/README.md)。设计探索保存在 [docs/design-options](docs/design-options/)，字体授权保存在 [Resources/Fonts](Shouxia/Resources/Fonts/)。
