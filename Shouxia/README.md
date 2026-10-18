# Video Extractor 原生客户端

当前版本 1.4.1，macOS 14+ / Apple Silicon。产品介绍、功能表和平台样例见 [项目首页](../README.md)；普通用户按 [Mac 安装说明](../docs/INSTALL-MAC.md) 使用发行包即可，无需构建源码。

## 日常操作

- 主窗口粘贴单视频链接或整段分享文字，选择视频 / 音频、保存文件夹和画质，点击提取。清空按钮和 Esc 清除输入；不会取消已提交任务。
- 视频画质：最佳、4K（2160p）、2K（1440p）、1080p、720p、480p。源站没有所选清晰度时选不超过上限的可用源；MP3 不使用视频清晰度。兼容 MP4 只限制源格式，不负责转码。
- 菜单栏或主窗口“快捷输入”可快速提交，点击查看任务回到主窗口。
- 失败显示简短原因，可原参数重试或修改后重试；下载成功但保存失败时，可更换文件夹后重试保存。
- 同一链接分别提取视频、音频或不同参数时，完成记录各自保留。移除记录不会删除媒体。
- 设置采用草稿，点击保存并关闭后生效；取消放弃编辑。导入文件、删除文件、检查更新等维护动作会明确即时执行。
- 网站访问辅助默认关闭。用途、选浏览器原因及权限方法见安装说明。成功读出 Cookie 不代表登录；支持域名范围不代表所有平台都具备解析器。
- 本地剪辑继续使用原生 AVFoundation：默认原尺寸、16:9、21:9、4:3等常用比例，自定义比例 / 像素宽高、可缩放预览、0.25–2× 倍速与新 MP4 导出。不会覆盖原文件。本次只验证画面比例、自定义尺寸及对应短片导出。

## 开发依赖

| 依赖 | 用途 |
| --- | --- |
| macOS 14+、Apple Silicon | 构建和运行原生界面 |
| Xcode Command Line Tools / Swift 5 编译模式 | `xcrun swiftc` 构建；系统框架 SwiftUI、AppKit、AVFoundation、Security 和 SQLite |
| Python 3.11+ | 维护者运行安装器测试和打包；不要求最终用户安装 |
| Git | 源码版本 / 发行 manifest |
| 固定 Colima / Docker CLI / Lima 运行资源 | 打包者提供 `--runtime-root`，版本见 runtime.env |
| 联网 | 初次后台初始化；具体网站下载和引擎更新 |

本地构建不等于后台初始化。开发机器若没有后台，应先使用发行安装器准备环境；`Shouxia/install.sh` 只安装自己构建的 App。

## 构建和非剪辑测试

在仓库根目录：

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
# 先退出当前客户端，再安装开发构建
bash Shouxia/install.sh
```

构建输出 `Shouxia/build/Video Extractor.app`。使用本机 ad-hoc 签名；稳定面向公众分发需维护者使用 Developer ID 签名、公证，并验收干净 Mac。打包脚本不会带本机偏好、数据库或下载文件。

## 制作原生发行包

先提交源码并构建，以便 manifest 中的 HEAD 与程序源代码一致。`--runtime-root` 下必须有 `bin/{colima,docker,limactl}` 和 `share/lima`；打包脚本验证固定版本。

```sh
python3 distribution/macos/package_native.py \
  --app 'Shouxia/build/Video Extractor.app' \
  --runtime-root "$HOME/.local" \
  --output distribution/output/native-1.4.1
```

输出版本由 App Info.plist 决定，包括 ZIP、SHA256SUMS、安装说明和 ORIGINAL-MANIFEST。ZIP 包含原生 App、运行组件、抖音插件、安装器与授权说明。需要在解压目录再运行 `安装原版.command --verify-only`，核对版本 / sourceCommit 与已推送提交，再发布 GitHub Release。

MeTube 和 yt-dlp 上游分别见 [MeTube](https://github.com/alexta69/metube)、[yt-dlp](https://github.com/yt-dlp/yt-dlp)。固定镜像提供 Python、FFmpeg、Deno 和 curl_cffi，安装前会核对必需能力。现有后台若有活动任务，安装器会停止插件变更；用户完成任务后再重试。运行组件冲突不会自动覆盖。

## 代码导航

| 模块 | 文件 |
| --- | --- |
| 主窗口 / 快捷输入 | `Sources/MainView.swift` |
| 设置 / 指南 | `Sources/DownloadSettings.swift`、`Sources/QuickStartView.swift` |
| 任务 / 提交 / 保存 | `Sources/Store.swift`、`Sources/Models.swift`、`Sources/Submission.swift`、`Sources/Destination.swift` |
| 参数 / 错误 | `Sources/DownloadPolicy.swift` |
| 浏览器读取与会话生命周期 | `Sources/BrowserCookieReader.swift`、`Sources/BrowserCookies.swift`、`Sources/BrowserSessionStore.swift`、`Sources/TaskCookies.swift` |
| 后台 / 引擎 | `Sources/Backend.swift`、`Sources/RuntimeSupport.swift`、`Sources/EngineUpdater.swift` |
| 抖音分享页补充 | `BackendPlugins/yt_dlp_plugins/extractor/shouxia_douyin.py` |
| 剪辑 / 画布 / 导出 | `Sources/ClipEditor.swift`、`Sources/ClipCanvas.swift`、`Sources/ClipExporter.swift` |

## 画面比例的定向测试

```sh
bash Shouxia/test-clip-aspects.sh          # 比例 / 边界 / 编辑器状态
bash Shouxia/test-clip-aspects.sh --export # 额外生成短测试视频，验证实际导出
```

实际导出夹具需要维护者的本机FFmpeg（默认`~/.local/bin/ffmpeg`，也可通过`SHOUXIA_FFMPEG`指定），这不是普通用户的安装依赖。覆盖原尺寸、21:9、自定义5:4和1280×1024，检查横屏与旋转视频的尺寸、音轨、居中内容和黑边。

## 其他可选剪辑回归（本轮未重复执行）

```sh
bash Shouxia/test-clips.sh
bash Shouxia/test-clip-timeline.sh
bash Shouxia/test-clip-canvases.sh
```

不要将真实 Cookie、浏览器数据库、带身份信息的分享参数、运行日志、用户历史、媒体或 VM 磁盘提交源码或上传 Release。

## 隔离的 2K / 4K / MP3 集成测试

```sh
bash distribution/tests/run-quality-smoke.sh
```

需要已安装的本地 Docker 后台。脚本创建不发布端口的临时 MeTube 容器，在容器内生成 720p / 1440p / 2160p 的短 HLS 测试源，实际通过提交 / 历史 API 下载，并用 ffprobe 验证输出分辨率、音轨和 MP3。结束删除自身容器，不读取浏览器数据，不写日常服务历史。为获取合成源，只有临时容器开启内部地址访问；正式后台不更改该设置。
