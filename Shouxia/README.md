# Video Extractor

为 Felix 制作的原生 macOS 影音下载工具。SwiftUI 主窗口与菜单栏共享任务，连接这台电脑已有的 MeTube 服务。

## 使用

打开 `~/Applications/Video Extractor.app`，也可以双击桌面的「Video Extractor」。首次连接会自动启动现有下载服务。

1. 粘贴视频网址或包含一个网址的分享文字，也可拖入链接。
2. 选择视频清晰度或 MP3 音频，点击「提取」或按 ⌘↩。
3. 查看实际下载进度；完成后打开文件、在 Finder 中显示，或把文件拖出。

点击「保存到 / 更改」选择输出文件夹；提交时记录本次任务的保存位置，后续更改不会影响旧任务的自动保存位置；失败任务点击「重试保存」时使用当前选择的文件夹，也可点击「选择文件夹并重试」。保存错误直接显示原因与位置。下载缓存保留在 `~/Downloads/MeTube`。关闭窗口后菜单栏入口仍可使用；退出应用不会停止后台下载。需要释放后台资源时，使用桌面 `MeTube视频下载/停止MeTube.command`。

支持范围由已安装 yt-dlp/MeTube 决定。YouTube、Bilibili、抖音、X 的具体链接可能受登录、地区、版权或平台变化影响。支持手动 Cookie 导入和可选的浏览器自动同步，操作见下文。2026-10-01 的六个平台实测中，YouTube、Bilibili、TikTok、X 样例成功，Instagram 样例无可下载格式，抖音样例要求新鲜 Cookie；这不代表整个平台的所有链接都能下载。视频默认使用源站原始最佳格式；MP4 选项只选择源格式，不转码。音频转为 MP3。

## 1.2.0 浏览器 Cookie 自动同步

自动同步默认关闭。在「下载设置 → 浏览器登录状态」开启开关，选择 Chrome、Edge、Firefox 的标准本机用户配置，或 Safari 默认 Cookie 存储，再点击「保存浏览器 Cookie 设置」。修改先保留在界面草稿中，保存后才生效；切换或刷新不会读取 Cookie。首次启用需要下载后台空闲，可能备份并重启后台以支持独立任务参数。

提交或重试抖音、YouTube、Bilibili、TikTok、Instagram、X、小红书、快手链接时，应用重新读取所选配置中对应平台的 Cookie；已知短链映射到所属平台，其他域名不触发读取。Chrome / Edge 解密可能弹出 macOS Safe Storage 钥匙串授权；Safari 可能需要在「隐私与安全性 → 完全磁盘访问权限」允许本应用，并重新打开应用。不会绕过系统授权。Firefox 不读取容器或分区会话；不混用其他用户配置。

需要登录时，点击「打开所选浏览器」，在浏览器内切换到所选用户配置并登录网站，再重试。没有找到配置时，打开浏览器后点击「刷新配置」；已保存配置消失时，重新选择并保存。状态仅反映同步或读取结果，不能确认网站登录有效性。Cookie 过期、平台风控、付费访问、地区限制及 DRM 仍可能阻止下载；权限被拒绝或加密版本不兼容时，可关闭自动同步并使用手动导入。

同步仅在本机发生，不读取密码、历史记录或云端浏览器数据。每次请求生成独立私有 Cookie 文件，目录权限 0700、文件权限 0600，存放在已验证的本机 MeTube 下载挂载中；设置、日志和请求正文不保存 Cookie 值，请求只提交内部生成的文件路径。同步阶段可取消，尚未提交到下载后台。后台确认任务结束后清理会话文件，未决任务保留以便恢复核对；「清理闲置自动会话文件」保留活动任务所需文件。关闭自动同步停止后续读取。

「手动导入 Cookie」继续支持自己导出的 Netscape 文本文件（最多 1 MB）。导入、删除与自动会话文件分开管理。自动同步失败时不会静默使用旧自动文件；没有可用站点 Cookie 时尝试公开访问。开发测试只使用合成 Cookie、SQLite 和加密样本，真实账户授权应由用户在应用中完成。

## 截取片段

已完成的视频点击剪刀按钮，或从「文件 → 截取本地视频…」（⇧⌘K）选择本地视频。拖动时间线的「开始」「结束」节点选择高亮片段，点击轨道定位画面；播放／暂停共用一个随状态变化的按钮，也可输入时间微调；点击「预览片段」核对后导出新的 MP4。默认选取前 10 秒，不会自动导出。播放按钮旁可选择常用倍速或输入 0.25–2 倍自定义速度，预览和导出都使用当前倍速；导出时长为选中时长除以倍速，画面与音频同步变速。支持取消、错误提示和在 Finder 中显示结果，原文件不会被覆盖。第一版每次导出一个片段，使用系统 AVFoundation 在本机处理；长片段和高分辨率导出仍会消耗计算资源。

## 快捷输入与引擎更新

点击主界面小粽子或「快捷输入」，打开类似 Spotlight 的浮动输入框，自动聚焦，粘贴后点击提取即可；菜单栏也提供输入入口，没有注册全局快捷键。

设置中默认开启自动更新。应用运行期间每天检查官方 PyPI 的 yt-dlp nightly，空闲时更新，下载队列或待处理任务存在时延后；失败后保留或恢复备份，并在界面显示状态。可以手动检查。退出应用后不检查，重新打开后继续。更新前验证依赖兼容性，不兼容时保留当前引擎。异常中断后根据本工具的事务记录恢复。MeTube 网页等外部客户端同时提交任务仍存在极小竞争窗口，维护时建议仅使用桌面应用。

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
bash Shouxia/test-store.sh
bash Shouxia/test-backend.sh
bash Shouxia/test-runtime.sh
bash Shouxia/test-submissions.sh
bash Shouxia/test-browser-cookies.sh
bash Shouxia/test-browser-session.sh
bash Shouxia/test-clips.sh # 可追加一个带音轨的视频路径，验证 1.5 秒短片导出
bash Shouxia/test-clip-timeline.sh
bash Shouxia/test-update.sh
bash Shouxia/build.sh
bash Shouxia/install.sh
```

更新前先退出「Video Extractor」。构建输出为 `Shouxia/build/Video Extractor.app`，安装脚本复制到用户 Applications 并创建桌面入口。采用本机 ad-hoc 签名，未进行 Apple 公证。

`Models.swift` 负责数据、分享链接解析和文件范围校验；`Backend.swift` 负责本机接口及运行时启动；`Store.swift` 管理状态；其他 Sources 文件提供原生界面。

## 任务分类与快捷入口

视频／音频选项同时筛选对应任务，支持全部、进行中和已完成。点击“管理记录”可勾选或全选当前列表的历史记录，批量移除时保留文件；切换分类会清空勾选。保存失败的记录也可以移除，下载缓存和已保存文件均保留；仅正在写入文件时暂时禁止移除。

快捷入口为 320pt 两行面板：链接输入及提取按钮、保存文件夹及更改操作。回车可提交，沿用主窗口选择的格式与画质。错误或连接异常时才额外显示提示。配色、字体与控件样式沿用原版。


## 1.1.0 下载可靠性更新

支持抖音精选页链接规范化、手动 Cookie 管理、代理与请求头、原始最佳格式、修正后重试、解析取消与未决任务核对、独立失败筛选和快捷输入反馈。MP4 选项选择源格式，不代表转码。需要登录态的平台仍需有效 Cookie。

测试入口：`test.sh`、`test-backend.sh`、`test-runtime.sh`、`test-submissions.sh`、`test-store.sh`、`test-clips.sh`、`test-clip-timeline.sh`、`test-update.sh`。完整验证记录见 `docs/superpowers/specs/2026-10-18-short-video-validation.md`。
