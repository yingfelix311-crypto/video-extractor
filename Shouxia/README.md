# 收下

为 Felix 制作的原生 macOS 影音下载工具。SwiftUI 主窗口与菜单栏共享任务，连接这台电脑已有的 MeTube 服务。

## 使用

打开 `~/Applications/收下.app`，也可以双击桌面的「收下」。首次连接会自动启动现有下载服务。

1. 粘贴视频网址或包含一个网址的分享文字，也可拖入链接。
2. 选择视频清晰度或 MP3 音频，点击「收下」或按 ⌘↩。
3. 查看实际下载进度；完成后打开文件、在 Finder 中显示，或把文件拖出。

文件保存到 `~/Downloads/MeTube`。关闭窗口后菜单栏入口仍可使用；退出应用不会停止后台下载。需要释放后台资源时，使用桌面 `MeTube视频下载/停止MeTube.command`。

支持范围由已安装 yt-dlp/MeTube 决定。YouTube、Bilibili、抖音、X 的具体链接可能受登录、地区、版权或平台变化影响；此版本没有账户 Cookie 导入界面，也未逐个平台验证。视频优先 MP4，音频转为 MP3；直链按原始画质保存。

## 本机环境

- macOS 14+，当前构建仅适用于 Apple Silicon。
- 此安装依赖当前 Mac 的 `~/.local/bin/colima`、`docker`，Colima profile `metube`、容器 `metube`。
- 服务固定为 `http://127.0.0.1:8081`，不会对公网开放。
- 容器必须保持原有 `~/Downloads/MeTube:/downloads` 挂载及 `DELETE_FILE_ON_TRASHCAN=false`（默认值），以使「移除记录」保留文件。
- 不是可复制到任意电脑即用的通用分发包；没有付费服务依赖。
- 日志：`~/Library/Application Support/Shouxia/backend.log`，可从帮助菜单打开。

## 开发

无需 Xcode 工程或第三方 Swift 包，已安装 Apple Command Line Tools 即可。

```sh
bash Shouxia/test.sh --live
bash Shouxia/build.sh
bash Shouxia/install.sh
```

更新前先退出「收下」。构建输出为 `Shouxia/build/收下.app`，安装脚本复制到用户 Applications 并创建桌面入口。采用本机 ad-hoc 签名，未进行 Apple 公证。

`Models.swift` 负责数据、分享链接解析和文件范围校验；`Backend.swift` 负责本机接口及运行时启动；`Store.swift` 管理状态；其他 Sources 文件提供原生界面。
