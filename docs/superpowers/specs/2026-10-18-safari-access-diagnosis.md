# Safari 自动 Cookie 访问故障

用户给出的完整抖音分享文本已成功提取 `https://v.douyin.com/CZcTY8t3ZYA/`，本机无 Cookie 的 HTTPS 请求正常 200 跳转至 `https://www.douyin.com/video/7692712648774080610?previous_page=web_code_link`。

应用持久设置为 Safari/Default、自动同步已开启。失败提交保留的原始错误明确为 Safari Cookie 访问被 macOS 拒绝，后台 queue/done/pending 均空，任务尚未到下载器。实际系统设置 → 隐私与安全性 → 完全磁盘访问权限中，Video Extractor 开关为 off。

根因是本机访问授权未开启。应用原来又把此原始错误归类成泛化“需要有效 Cookie”，掩盖了恢复步骤。现对精确的本地 Safari 权限错误先显示“Safari 访问权限不足”，提供授权、退出重开说明，保留原有设置入口。未改变系统权限、浏览器选择或自动开关。

核心回归先以旧标题断言失败，修复后通过；浏览器读取和自动同步生命周期测试通过；构建和严格签名验证通过。独立小范围审查通过。安装 1.2.1/build 4，二进制与构建相同，SHA256 `65b8d28c00aa7b9e73865053773de38e3c5990dc2e37234f78b104320b81e75f`。实际窗口确认新标题已显示，已保留用户的分享文本并打开系统权限页面。

授权需要用户本人完成。开启权限、退出重开应用并确认 Safari 已登录抖音后才可继续验证视频下载；目前没有宣称该视频下载成功。升级前备份 `/Users/felix/Library/Application Support/Shouxia/app-backups/safari-permission-20261018-012332/Video Extractor.app`。

## 后续：旧授权绑定和提取器兼容问题

以上记录是 1.2.1 首次诊断时的状态。用户打开权限后仍失败，继续检查 tccd 日志，发现 macOS 保存的旧要求绑定 1.2.0 CDHash `de4bba7066d56aafb1a53d1077439cf217ea466b`，与当前 1.2.1 CDHash `7c20f3ce9118dcbd84db8fed614b83e4805ded4b` 不符。开关为 on 并不代表当前 ad-hoc 签名二进制已匹配。用户明确同意修复权限绑定，并本人完成系统验证；随后通过系统设置移除旧条目、添加当前应用、开启并退出重开。

修复后实际读取 62 条未过期相关 Cookie，包含 sessionid / sid_tt 等登录键；没有保存或输出值。Safari 网页可播放目标视频。MeTube 已收到请求，失败点移到 yt-dlp DouyinIE 的 detail API；其 Fresh cookies 文案并非系统权限错误，也不证明会话过期。更换 Safari UA 与匹配 TLS 请求仍失败。当前上游实现亦无备用路径。

实测当前任务的相同 Cookie 加 Android 分享页请求，返回 `videoInfoRes.item_list` 中精确 `aweme_id=7692712648774080610` 的视频。页面提供的播放地址返回 HTTP 206 / video/mp4 / MP4 文件头。加入后端 yt-dlp 分享页备用提取插件；8 项自动化测试通过，原缺失路径先复现失败。原生二进制未重建，保持现有权限绑定。真实应用已完成下载和导出，文件 67,331,560 字节、H.264 720×1280 / AAC，实际时长 233.430 秒。完整结果见 `2026-10-18-douyin-share-fallback-validation.md`；页面标称规格与最终媒体有差异，验收以实际文件为准。
