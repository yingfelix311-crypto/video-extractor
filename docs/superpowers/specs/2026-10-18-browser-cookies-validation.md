# 浏览器 Cookie 自动同步验证

最终代码 `41c7a1d`，macOS 应用 1.2.0/build 3，安装在 `/Users/felix/Applications/Video Extractor.app`。

支持 Chrome/Edge 标准本机配置与 macOS v10 加密、Firefox 普通非容器/非分区会话、Safari 默认 Cookie 存储。自动读取默认关闭，选择配置并保存后才在支持的平台请求中读取。没有访问真实浏览器 Cookie 或钥匙串进行开发测试，真实账号首次系统授权留给用户完成。

## 检查与实测

- 10 组 shell 测试全部通过：test.sh、test-backend.sh、test-runtime.sh、test-submissions.sh、test-store.sh、test-clips.sh、test-clip-timeline.sh、test-update.sh、test-browser-cookies.sh、test-browser-session.sh。
- 新读取测试覆盖严格域边界、过期与 Netscape 注入、配置遍历/符号链接、Firefox 会话隔离、Chrome/Edge v10 与主机摘要、错误密钥与未知加密、Safari 二进制边界、非普通文件和有期限的 FIFO 子进程回归。
- 新流程测试覆盖显式启用、未启用/未知平台零读取、配置传递、0600/0700 私有任务路径、缺少 Cookie 公开回退、权限错误、同步阶段取消不调用后台全局取消、重启恢复、未知 HTTP/协议结果保留文件并阻止重复提交、读取前运行环境拒绝零读取、首次未选配置不误称旧配置失效。
- 真实 MeTube 使用虚构 `.example.invalid` Cookie 及独立任务目录下载 W3C Sintel 视频，4,372,373 字节，SHA256 `b670602fa00934ca27c4351bb0efe7ea7a07fae57284e44226025eeed7c51254`。引擎回写后文件仍为 0600，手动 Cookie 状态不变，测试任务/下载文件/会话目录已删除。
- 各任务独立审查与整项审查通过；修复 FIFO 阻塞、离线诊断禁用、未知响应误判、读取前环境验证，以及首次配置提示问题。
- 全 Sources 类型检查、最终原生构建、`codesign --verify --deep --strict` 通过。安装字节与最终构建相同：SHA256 `b6272bb202bd7ae49221f545fe5447cf886a3665564ce7f4d35e58d2d3fc3f55`。
- 最终实际窗口已确认自动开关关闭、Chrome 可用配置正确显示、手动导入保留、服务就绪；设置页留在屏幕上供用户完成首次选择。截图在 `/Users/felix/Documents/ChatGPT/个人工具/stacher-comparison-2026-10-18/implementation/05-browser-cookie-settings.png`。

升级前 1.1.0 完整备份：`/Users/felix/Library/Application Support/Shouxia/app-backups/browser-cookies-20261018-011345/Video Extractor.app`。下载历史和保存目的地仍在。改动保留在 `codex/short-video-completeness`，没有推送、发布或创建 PR。
