# Safari 自动 Cookie 访问故障

用户给出的完整抖音分享文本已成功提取 `https://v.douyin.com/CZcTY8t3ZYA/`，本机无 Cookie 的 HTTPS 请求正常 200 跳转至 `https://www.douyin.com/video/7692712648774080610?previous_page=web_code_link`。

应用持久设置为 Safari/Default、自动同步已开启。失败提交保留的原始错误明确为 Safari Cookie 访问被 macOS 拒绝，后台 queue/done/pending 均空，任务尚未到下载器。实际系统设置 → 隐私与安全性 → 完全磁盘访问权限中，Video Extractor 开关为 off。

根因是本机访问授权未开启。应用原来又把此原始错误归类成泛化“需要有效 Cookie”，掩盖了恢复步骤。现对精确的本地 Safari 权限错误先显示“Safari 访问权限不足”，提供授权、退出重开说明，保留原有设置入口。未改变系统权限、浏览器选择或自动开关。

核心回归先以旧标题断言失败，修复后通过；浏览器读取和自动同步生命周期测试通过；构建和严格签名验证通过。独立小范围审查通过。安装 1.2.1/build 4，二进制与构建相同，SHA256 `65b8d28c00aa7b9e73865053773de38e3c5990dc2e37234f78b104320b81e75f`。实际窗口确认新标题已显示，已保留用户的分享文本并打开系统权限页面。

授权需要用户本人完成。开启权限、退出重开应用并确认 Safari 已登录抖音后才可继续验证视频下载；目前没有宣称该视频下载成功。升级前备份 `/Users/felix/Library/Application Support/Shouxia/app-backups/safari-permission-20261018-012332/Video Extractor.app`。
