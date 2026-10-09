# Video Extractor · 独立发行版

macOS / Windows 共用的桌面客户端，保留深色、紫色与黄绿色设计。安装包内置 yt-dlp、FFmpeg 和 ffprobe；不需要另行安装 Python、Docker 或 MeTube。旧 SwiftUI 客户端源码继续保存在 `Shouxia/`。

## 使用

1. macOS 14+ Apple Silicon：打开 DMG，将应用拖入 Applications。Windows 10/11 x64：运行 EXE 安装程序，按提示安装到当前用户目录。
2. 粘贴公开视频链接，选择视频画质或 MP3，点击提取。
3. 文件保存到选择的目录；每个任务记住所选位置；更换目录后重试失败任务会使用新位置。同名文件自动改名，不覆盖已有文件。
4. 已完成的视频点击剪刀，或从「截取本地视频」选择视频。拖动开始／结束节点，设置 0.25–2x 倍速，预览后导出新的 MP4。
5. 任务菜单提供「移除记录，保留文件」和「删除记录和文件」两个明确选项。文件删除失败时保留记录并提示错误。

文件记录独立保存在 Electron userData 下的 tasks.json。客户端不扫描下载目录导入旧记录，不创建自动订阅，不读取旧 MeTube 历史。退出中断的任务重开后显示为已中断，需要手动重试。视频不上传至第三方处理。

## 当前范围

- 自包含测试版：尚未配置 Developer ID / Windows 代码签名证书，macOS 尚未公证。系统可能阻止首次启动；正式公开发行前需要开发者签名与公证。安装说明不应指导用户关闭系统保护。
- Windows 包通过 GitHub Actions 的 Windows 机器构建。自动验证不替代真实 Windows 电脑的安装和操作验收。
- 下载网站支持由打包的 yt-dlp 版本决定；需要登录的链接可能失败，当前没有 Cookie 导入 UI。
- 预览依赖 Chromium 支持的编码；MP4 H.264 / WebM 是常用格式。其他文件格式可以在系统播放器中打开，界面会提示无法预览。
- 本版暂不提供菜单栏粽子入口和自动引擎升级；引擎随应用版本一起更新，避免更新破坏签名或运行环境。
- 为降低负载，下载队列串行处理，片段每次导出一个，FFmpeg 限制视频编码线程。高分辨率长片段仍会使用更多资源。

## 构建

Node.js 24+。在 `desktop` 目录执行：

```sh
npm ci
npm run engines
npm test
npm run smoke
# macOS arm64
npm run package:mac
# Windows x64，在 Windows 机器执行
npm run package:win
```

`engines` 从固定版本的官方 yt-dlp release 和 eugeneware/ffmpeg-static release 获取对应平台工具，yt-dlp 验证官方 SHA-256，记录三个工具的 SHA-256。许可证随包提供。`smoke` 使用临时的 3 秒低分辨率合成视频，验证 4 个倍速、音轨、原文件保留、防覆盖、取消和删除后的重新加载；不下载测试视频，结束清理合成数据。

产物在 `desktop/dist`。源码、构建工作流可提交，`node_modules`、下载引擎及安装包不提交 Git。GitHub Actions 保存构建产物 30 天；发布到 Releases 应使用固定版本、校验和及明确的测试状态。
