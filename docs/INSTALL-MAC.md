# Mac 安装与运行

本次发行是 Video Extractor **1.4.1 原生 SwiftUI / AVFoundation 版**。支持 Apple Silicon（M 系列）、macOS 14 及以上；Windows、Intel Mac 不在本安装包范围内。

## 安装

1. 使用有仓库权限的 GitHub 账号打开 [1.4.1 下载页](https://github.com/yingfelix311-crypto/video-extractor/releases/tag/native-v1.4.1)，下载 `Video-Extractor-Native-1.4.1-macOS-arm64.zip`。GitHub 自动生成的 Source code ZIP 是源码，不是安装包。
2. 解压完整文件夹，退出旧版 App，双击 `安装原版.command`。不要把 App 单独拖走，安装器还需要同目录的 runtime、插件和校验文件。
3. 安装器校验文件，准备运行组件，联网初始化下载后台，检查下载引擎及插件后安装并打开应用。安装到 `~/Applications/Video Extractor.app`。如果失败，保留安装文件夹，按简短原因处理后再次运行；它会核对并恢复自身的初始化。
4. 打开后粘贴单视频链接或分享文字，选择保存文件夹，点击 **提取**。音频请选择 **音频**，输出 MP3。先使用“最佳画质”和默认关闭的“网站访问辅助”。

首次安装需要互联网，安装器会下载虚拟机基础镜像、固定 MeTube 镜像和指定 yt-dlp。耗时随网络变化。无需手动安装 Homebrew、Docker Desktop、Python、Node 或 FFmpeg；这些操作不属于用户上手步骤。

**系统信任限制：** 当前为 ad-hoc 签名的测试发行包，未通过 Apple 公证，macOS 可能限制首次打开。如果系统提供“隐私与安全性 → 仍要打开”且你确认包来自本仓库，可按系统流程确认。不要关闭 Gatekeeper。正式无障碍分发需要维护者提供 Developer ID 签名与公证；本版不声称已完成干净 Mac 的完整首次安装验收。

## 浏览器辅助：可选，先不配置

公开链接可直接尝试。网站明确要求登录或需要尝试已有网站会话时，在 **设置 → 网站访问辅助** 中开启，选择你实际使用的浏览器和用户配置，点击 **保存并关闭** 后重试。选择表示读取该浏览器配置对应平台的 Cookie；与复制链接的浏览器、系统默认浏览器无关。

- Chrome / Edge：macOS 可能请求钥匙串访问，用户在系统窗口授权。
- Safari：仅实际读取被拒绝时，在系统“隐私与安全性 → 完全磁盘访问权限”为**当前安装的** Video Extractor 开启，然后退出并重开 App。新版本替换签名后，系统可能再次要求确认权限；无需给所有用户预先开此权限。
- Firefox：标准本机配置；当前不读取容器、分区会话。Safari 使用默认存储。
- Cookie 不一定是登录账号，也可能是访客状态；无法保证网站接受。失败时可“本次不读取浏览器”重试；不改变持久开关，手动导入文件仍独立存在。

不要向维护者发送 Cookie、密码或浏览器数据库。设置中的高级区域支持手动 Netscape Cookie 文件（最多 1 MB）、删除和会话清理。

## 运行组件与存储

| 内容 | 位置 / 配置 |
| --- | --- |
| App | `~/Applications/Video Extractor.app` |
| 运行组件 | `~/.local/bin`、`~/.local/share/lima`；Colima 0.10.3、Docker CLI 29.8.2、Lima 2.2.0 |
| 虚拟机 | Colima `metube` profile；2 CPU、2 GiB 内存、20 GiB 虚拟磁盘容量（不是安装包大小） |
| 服务 | Docker `colima-metube` context、`metube` 容器，HTTP 仅 `127.0.0.1:8081` |
| 缓存 | `~/Downloads/MeTube`，绑定容器 `/downloads` |
| 解析插件 | 缓存下 `.shouxia/yt-dlp-plugins`；安装器校验抖音插件后部署，变更时保留上一份 |
| 本机数据 | `~/Library/Application Support/Shouxia`、当前用户偏好；后台记录在缓存 `.metube` |

初始 MeTube 镜像 digest 与 yt-dlp 版本固定在 `distribution/macos/runtime.env`；后台镜像提供 FFmpeg/ffprobe、Python、Deno 和 curl_cffi。安装器校验所需运行能力及抖音 Android 模拟请求支持。之后空闲更新功能可升级 yt-dlp；它不是整个 App 的自动升级。

已有相同运行组件和兼容后台会复用。组件版本或 profile 冲突会停止，不覆盖其他环境。已有用户后台不重新安装下载引擎；插件配置只在无活动任务时更新，变更插件后重启服务。安装器不带作者的 Cookie、下载文件、历史、订阅、容器状态或虚拟机磁盘，不创建订阅。

## 简单排查

| 提示 / 情况 | 操作 |
| --- | --- |
| 链接失效或视频不存在 | 在网页确认可播放，重新复制有效的单视频完整分享链接 |
| 网站未提供可下载视频 | 重试其他有效视频；登录或换浏览器不一定能解决 |
| 所选格式不可用 | 切换最佳画质和原始最佳格式 |
| 网站要求登录 | 在所选浏览器配置登录对应网站，开启网站访问辅助后重试 |
| Safari 访问权限不足 | 按上文开启当前 App 的权限，重启后重试，或本次不读取浏览器 |
| 下载成功但保存失败 | 选择可写文件夹，点重试保存，无需重新下载 |
| 服务未连接 | 等待启动，重新连接；仍失败时运行安装器 `--check` |
| 快手暂不支持 | 当前缺少解析器；不要反复导入 Cookie |

2K / 4K 是源站格式上限，低清源不会变高清。某些平台会限流、拒绝当前网络或变更解析方式，详见根目录的实际样例表。

## 检查、停止与卸载

在解压目录的终端执行：

```sh
bash 安装原版.command --plan        # 只展示安装步骤
bash 安装原版.command --verify-only # 只核对安装文件校验和
bash 安装原版.command --check       # 检查已安装运行组件、后台与插件，不启动/修改后台
```

退出 App 保留后台运行。停止后台资源使用：

```sh
~/.local/bin/colima stop --profile metube
```

需要时打开 App 并重新连接即可启动。只卸载客户端：退出 App，把 `~/Applications/Video Extractor.app` 移到废纸篓。不会自动删除已保存媒体、缓存和历史。运行组件可能供其他项目使用，不应盲目删除；完整清理前先备份用户数据并核对共享情况。

## 安装验证边界

发行验证包括原生构建与签名完整性、非剪辑回归、安装包逐文件 SHA256、已有后台检查、实际下载和质量选择，以及隔离夹具中的初始化中断恢复 / 冲突保护。固定的干净 MeTube 镜像单独检查了 FFmpeg、JavaScript 运行时和抖音请求模拟能力。尚未在另一台干净物理 Mac 完成从下载到首次启动的完整验收；没有把已配置好的作者机器结果冒充该验收。本轮针对画面比例和自定义尺寸做了定向预览／导出验证，没有重复其他剪辑回归。
