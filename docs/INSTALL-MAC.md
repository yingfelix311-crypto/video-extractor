# Mac 原版安装与运行

这是当前 SwiftUI / AVFoundation 原版的私有测试发行包。原版程序文件逐一与作者正在使用的 App 比对，界面、交互、剪辑实现和参数未替换。只支持 Apple Silicon、macOS 14+；不提供 Windows 版。

## 下载与安装

1. 登录有本仓库读取权限的 GitHub 账号，打开 [Mac 原版下载页](https://github.com/yingfelix311-crypto/video-extractor/releases/tag/native-v1.0.0)。下载 `Video-Extractor-Native-1.0.0-macOS-arm64.zip`，不要下载 GitHub 自动生成的 Source code ZIP。
2. 解压完整文件夹，先阅读说明。退出旧的原生 Video Extractor 后，双击 `安装原版.command`。不要单独拖出 App，安装脚本还需要旁边的 runtime 文件。
3. 脚本先校验文件与现有环境，再准备原版运行组件、下载并初始化 MeTube 后台，验证服务可用后复制原版 App 并打开。安装位置仍为 `~/Applications/Video Extractor.app`。
4. 首次配置需要联网，包含 Linux 基础镜像、MeTube 容器镜像及指定 yt-dlp 包；不能离线安装，耗时取决于网络。后台与原环境一样使用 2 CPU、2 GiB 内存、20 GiB 虚拟磁盘配置。20 GiB 是虚拟磁盘容量配置，不是安装包大小。

这是 ad-hoc 签名、尚未 Apple 公证的测试包。系统可能阻止第一次打开。正式无障碍分发需要 Developer ID 签名和公证；请勿关闭 Gatekeeper 或其他系统保护。尚未在干净 Mac 完成完整首次安装验收，不能称为正式通用安装版。

## 完整保留的产品实现

- SwiftUI 主窗口、菜单栏入口、快捷输入、颜色、字体与控件。
- 同一套视频／MP3 下载提交与画质参数、保存失败提示和重试、任务管理。
- AVFoundation 原生视频预览、双节点时间线、播放／暂停、0.25–2× 倍速预览及同步音视频导出。
- 原版下载引擎检查、更新、延后及恢复机制；它更新下载引擎，不是整个应用的自动更新。

## 后台环境

安装包包含 Colima 0.10.3、Docker CLI 29.8.2、Lima 2.2.0 及所需 Lima 资源。使用 `metube` profile、`colima-metube` Docker context、`metube` 容器，端口 `127.0.0.1:8081`，挂载 `~/Downloads/MeTube:/downloads`。MeTube 镜像固定 digest，新环境初始化 yt-dlp 为原机快照版本；之后由原版自动更新逻辑维护。

已有工具或配置不同会明确停止，不会覆盖其他运行环境。已有兼容环境会复用，不导入作者的任务、订阅、账户、视频、容器状态或虚拟机磁盘。安装脚本不创建频道或播放列表订阅。新后台初始化失败时，保留绑定容器 ID 的安装记录；再次运行只恢复该安装器创建的同一容器，不会修改原有用户后台。

## 检查、停止与卸载

在解压目录的终端中执行：

```sh
bash 安装原版.command --plan        # 只展示步骤，不修改环境
bash 安装原版.command --verify-only # 只校验安装包
bash 安装原版.command --check       # 只检查已安装环境，不启动或修改后台
```

退出应用仍保留后台运行，这是原版行为。需要停止资源使用时，执行 `~/.local/bin/colima stop --profile metube`。

卸载客户端只把 `~/Applications/Video Extractor.app` 移入废纸篓。视频在所选目录和 `~/Downloads/MeTube`，历史在本地后台及 `~/Library/Application Support/Shouxia`；卸载程序不会自动删除它们。Colima/Docker/Lima 可能被其他工具使用，不应直接删除。完整清理后台前，请先备份视频和记录，再联系维护者确认。

## 验证范围

已核对原版程序逐文件一致性、安装包校验、安装脚本语法、运行组件冲突保护、已有 profile 保护、原生核心/任务测试及原机后台连通性。干净 Mac 首次虚拟机和容器初始化仍需真实环境验收。SHA256SUMS 与 ORIGINAL-MANIFEST 提供安装包和原版文件核对依据。
