# 可直接使用的项目介绍

下面是发布草稿，尚未代发到社区。发布时附上仓库链接、分享封面或演示；根据社区规则选择自荐版块。不要写“所有平台均支持”“无需网络初始化”“已获 Apple 公证”或“支持 Windows”。

## 中文短介绍

我做了一个原生 Mac 视频工具 Video Extractor：粘贴链接或分享文字，保存视频 / MP3，再截取想保留的片段。支持 2K / 4K 画质上限、原视频比例、16:9 / 21:9 / 4:3 等画布，以及自定义比例或像素尺寸。

目前是面向 Apple Silicon、macOS 14+ 的 1.4.1 测试版。安装器会自动准备本地运行组件，首次需要联网初始化。浏览器会话辅助默认关闭，只有网站需要时才设置；平台支持情况受源站和 yt-dlp 解析器影响。

仓库、安装说明与测试安装包都已公开，欢迎反馈安装和实际使用中卡住的地方。目前尚未 Apple 公证，首次打开可能需要系统确认。

项目：[Video Extractor](https://github.com/yingfelix311-crypto/video-extractor)

## English introduction

Video Extractor is a native Mac video/audio downloader and clip editor built with SwiftUI, AVFoundation and yt-dlp through a local MeTube backend. Paste a link or share text, save video or MP3, then select a time range and a standard or custom canvas ratio. Quality caps include 1440p and 2160p when available from the source.

The current 1.4.1 prerelease targets Apple Silicon and macOS 14+. The installer prepares local runtime components; first setup requires internet access. Optional browser-session assistance is off by default. Site compatibility depends on the source and extractor; this is not a guarantee of every platform or video.

The repository and test download are public. The current package is ad-hoc signed and has not been Apple-notarized. Feedback on installation and everyday usability is welcome.

Project: [Video Extractor](https://github.com/yingfelix311-crypto/video-extractor)

## 素材

- 分享封面：[`../images/social-preview.png`](../images/social-preview.png)，1280×640。
- 30 秒无声字幕流程演示：[`video-extractor-demo.mp4`](video-extractor-demo.mp4)。实机截图经剪辑，不是连续录屏或速度测试。
- [字幕文字与演示范围](TRANSCRIPT.md)。

## 后续观察

使用 GitHub 自带的 Insights → Traffic 查看访问量、克隆量和来源；根据真实反馈改进 README 和安装步骤。不承诺曝光或 Star 数，不购买虚假互动。
