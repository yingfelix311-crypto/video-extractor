# Video Extractor

原生 macOS 视频提取器，SwiftUI 界面，连接本机 MeTube / yt-dlp。

- 视频与音频提取、画质选择、真实任务进度
- 菜单栏小粽子入口、Spotlight 风格快捷输入框
- 自选保存文件夹，按任务记住目标位置
- yt-dlp 每日自动检查更新，空闲升级、异常恢复
- Sora / Manrope 字体，黑紫绿配色

## 在当前 Mac 上修改

```sh
# 验证代码（不下载视频）
bash Shouxia/test.sh
bash Shouxia/test-update.sh
# 构建
bash Shouxia/build.sh
# 先退出正在运行的应用，再安装
bash Shouxia/install.sh
```

当前构建需要 Apple Silicon、macOS 14+ 和 Apple Command Line Tools。后端依赖本机已配置的 Colima `metube` profile、Docker `metube` 容器、8081 端口以及 Downloads/MeTube 挂载；本仓库不是任意电脑上开箱即用的安装包。[详细运行说明](Shouxia/README.md)。

## 常见修改位置

| 需求 | 文件 |
|---|---|
| 主窗口、快捷输入、画质菜单 | `Shouxia/Sources/MainView.swift` |
| 配色和字体 | `Shouxia/Sources/Theme.swift` |
| 菜单栏单色粽子 | `Shouxia/Sources/ShouxiaApp.swift` |
| 彩色图标原图 | `Shouxia/Resources/Mascot.png` |
| 保存目录与安全导出 | `Destination.swift`、`Store.swift` |
| 引擎更新与恢复 | `Shouxia/Sources/EngineUpdater.swift` |
| 服务连接 | `Shouxia/Sources/Backend.swift` |

改彩色图标后执行 `bash Shouxia/rebuild-icon.sh`，再构建安装。字体授权保留在 `Shouxia/Resources/Fonts/`。历史设计探索与预览保留在 `docs/`。

## 同步 GitHub

```sh
git pull --ff-only
git status
git add <本次修改的文件>
git commit -m "描述这次修改"
git push
```

已配置上游后，修改完成执行以上提交和推送即可同步。不要提交 Cookie、账号凭据、下载视频或本机运行数据。默认保持私有仓库。

## 实测范围

2026-10-01 六条公开链接实测：YouTube、Bilibili、TikTok、X 下载成功；Instagram 样例无视频格式；抖音样例要求 Cookie。支持情况取决于具体链接、网络、登录状态及平台变化，自动更新不保证解除平台限制。
