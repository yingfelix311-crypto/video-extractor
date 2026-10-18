# macOS 正式分发准备

当前 `native-v1.4.1` 是 ad-hoc 签名、未获 Apple 公证的测试版。下面是维护者发布流程，不是普通用户的安装前置条件。

## 当前状态

| 项目 | 状态 |
| --- | --- |
| 公开仓库、公开 ZIP、安装文档 | 已提供 |
| 本机可用的 Developer ID Application 证书及私钥 | 2026-10-18 检查为 0 个 |
| 原生 App 签名 / 公证辅助脚本 | 已提供；尚未向 Apple 提交 |
| 整套安装器及运行组件的正式分发审查、公证 | 待完成 |
| 干净 Mac 从公开下载到完成导出的验收 | 待在独立环境执行 |

## 维护者的证书准备

由项目所有者在自己的 Apple Developer 账号和钥匙串中准备 **Developer ID Application** 证书及其私钥。涉及注册、付费、身份核验或协议的步骤由账号所有者完成。不要把密码、私钥或应用专用密码发到 Issue、代码仓库或聊天中。

```sh
security find-identity -v -p codesigning
xcrun --find notarytool
xcrun --find stapler
```

在本机交互式保存公证凭据：

```sh
xcrun notarytool store-credentials video-extractor-notary
```

按工具提示输入自己的 Apple ID、Team ID 和应用专用密码。脚本只接收钥匙串配置名，不接收这些秘密。

## 原生 App 的可执行流程

先构建，再把下方占位符换成 `find-identity` 显示的 40 位证书指纹。`--check` 仅检查本机条件，不证明配置可登录 Apple。

```sh
bash Shouxia/build.sh
python3 distribution/macos/notarize_app.py \
  --app 'Shouxia/build/Video Extractor.app' \
  --identity YOUR_40_CHARACTER_CERTIFICATE_SHA1 \
  --profile video-extractor-notary \
  --output distribution/output/app-notarized-candidate --check
```

条件齐备后，去掉 `--check` 执行。该脚本只接受当前原生 Bundle；发现额外可执行文件、嵌套 Mach-O 或符号链接会停止，要求逐项审查。它复制 App，使用 hardened runtime 和安全时间戳签名，提交 Apple，要求 `Accepted`，然后装订票据并执行 `codesign`、`stapler validate`、`spctl`。成功后才产生 `Video-Extractor-app-notarized.zip`。已有输出目录一律拒绝覆盖；源 App、已安装 App 和现有 GitHub 测试版不变。

这个 ZIP **仅包含 App**，不能替代当前整套安装包，也不能在缺少后台时独立使用。辅助脚本的成功不等于完整产品已达到正式分发条件。

## 完整安装器的发布门槛

当前安装器还分发 / 下载 Colima、Docker CLI、Lima、虚拟机镜像和 MeTube 引擎。逐个盘点 macOS 可执行文件的来源、签名、公证、权限和授权；保留第三方必要的签名与 entitlements，不能用 `codesign --deep --force` 批量覆盖。Linux 镜像不由 macOS App 的公证结果背书。

按 Apple 的自定义安装器流程，先完成 payload 的签名、公证，再把已公证 payload 放入最终安装器并对最终交付容器提交公证；网络安装器下载的 macOS 代码也需分别满足要求。若改成 PKG，还需要对应的 Developer ID Installer 证书。发布前为最终 ZIP / DMG / PKG 重新生成校验值和清单，保留旧版本，不直接替换同名已发布文件。

## 干净 Mac 验收记录模板

在另一台 Apple Silicon Mac，或全新的受支持 macOS 环境执行。不要把本机已有环境的测试写成干净安装通过。

| 步骤 | 通过标准 | 结果 / 证据 |
| --- | --- | --- |
| 环境 | 记录 macOS 版本、芯片；未预装本项目运行依赖 | 待测 |
| 匿名下载 | 未登录 GitHub 可下载公开 ZIP；SHA256 与发布清单一致 | 待测 |
| 首次启动 | 记录 Gatekeeper 的实际提示；不关闭系统保护 | 待测 |
| 初始化 | 安装器自动准备依赖，结束后服务可用；记录耗时和失败恢复 | 待测 |
| 直接链接 | 用仓库自制 `demo-source.mp4` 下载，文件可播放 | 待测 |
| 视频 / MP3 | 各提交一个任务，保存、打开、定位均可用 | 待测 |
| 源站画质 | 选 2K / 4K 上限；只对确实提供该格式的自有样例验收 | 待测 |
| 网站会话 | 默认关闭；仅在需登录的自有样例中选择实际登录的浏览器 | 待测 |
| 截取 | 原比例及自定义比例导出；核对时长、像素与原文件未变 | 待测 |
| 重启与卸载 | 重启后记录可用，退出不丢任务，卸载客户端不删除媒体 | 待测 |
| 冲突 / 离线 | 已有运行组件冲突时不覆盖；离线初始化给出简短原因 | 待测 |

问题反馈请去除 Cookie、账号信息、绝对路径和原始敏感日志。

## 依据

- [Apple：Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple：Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
