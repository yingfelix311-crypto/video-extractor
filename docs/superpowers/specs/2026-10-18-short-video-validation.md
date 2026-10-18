# Video Extractor 1.1.0 验证记录

已实现审计中八项可靠性与交互缺口，以及可选代理/Referer/User-Agent 和后台依赖诊断。保留 SwiftUI、MeTube、AVFoundation 和现有视觉；只更新本机软件，不发布 GitHub Release。

## 功能
- 抖音 modal_id 规范化；保留原地址；拒绝歧义 ID 和非法输入。
- 默认 any 原始最佳格式，可明确选择 MP4 源格式；音频仍 MP3，不声称 MP4 选择等于转码。
- 手动 Netscape Cookie 文件导入、校验、状态、清除；不读取浏览器账户。
- 提交即显示并持久化意图；可停止解析并核对，超时/取消核对失败保留未决记录，阻止重复提交。
- 修正后重试保留原目的地，可更改参数并明确采用当前网络设置；使用后台实际 URL 避免误删新记录。
- 视频/音频参数与列表筛选分离；失败筛选与数量；原始错误折叠、复制及对应恢复操作。
- 快捷输入显示参数，成功反馈保留；下载设置集中 Cookie、网络、引擎、诊断。
- 网络后台迁移保留完整 Config/HostConfig、可写镜像层和 bind 数据；失败或启动中断可恢复；原容器备份保留。

## 自动验证

以下脚本均通过：test.sh、test-backend.sh、test-runtime.sh、test-submissions.sh、test-store.sh、test-clips.sh、test-clip-timeline.sh、test-update.sh。包含真实子进程完成/超时、HTTP multipart、错误响应、取消后的核对失败、嵌套历史参数解码、已有导出/剪辑/引擎事务回归。

独立整体审查及隔离 fake backend 探针通过：取消后删除失败保留未决意图；短链接经后台归一到旧 URL 时不删除新完成记录。修复启动恢复失败导致轮询永久停止与维护并发问题。

## 真实环境

- MeTube 2026.09.29，yt-dlp 2026.10.10.233141；Deno 2.9.7、FFmpeg/FFprobe 7.1.5。Node 未安装；当前已有 Deno，未因此安装重复运行时。
- 实际网络配置迁移成功；比较完整 HostConfig 相等，Config 除有意变化的 Env/Image/Labels 外相等；可写层和 bind marker 均保留。模拟替代容器中断，恢复到精确原容器 ID，再迁移成功，原备份保留。
- 公开 W3C Sintel 样本通过真实 Backend → Store → MeTube 请求，携带 User-Agent 参数。下载 4,372,373 字节 MP4；导出文件与缓存逐字节一致。仅移除该测试任务和测试文件，未清除用户历史。
- 使用虚构 example.invalid Cookie 做真实导入/状态/0600 权限/删除验证，恢复原先未配置 Cookie 状态；无真实登录凭据参与。
- 安装的 1.1.0 已验证签名和编译产物一致；旧 app 保留在 ~/Library/Application Support/Shouxia/app-backups/20261018-004504/Video Extractor.app。
- 本机检查主窗口、下载设置、依赖诊断、修正重试、快捷输入参数和解析状态。用户抖音精选页在新版本已进入单视频提取器，仍返回 Fresh cookies，界面引导手动导入 Cookie。

## 明确边界

未取得或自动读取用户真实 Cookie；该抖音视频的成功下载仍取决于用户提供的有效 Cookie 及平台响应。其它短视频平台需具体样本逐项验证；不能承诺所有网站可下载。当前 MeTube 仍以 URL 为任务身份，不新增同 URL 并发多格式下载或批量多 URL 产品功能。
