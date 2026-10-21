#!/bin/bash
set -euo pipefail
base="$(cd "$(dirname "$0")" && pwd)"
mode="${1:-install}"
fail(){ printf '安装停止：%s\n' "$*" >&2; exit 1; }
case "$mode" in
 --plan)
  cat <<'TXT'
安装现有 SwiftUI / AVFoundation Mac 原版，不发布 Windows 版。
准备固定版本 Colima / Docker / Lima；使用 metube profile。
新环境：2 CPU / 2 GiB 内存 / 20 GiB 磁盘，VZ / virtiofs。
MeTube 仅监听 127.0.0.1:8081，下载缓存为 ~/Downloads/MeTube。
已有工具和后台先检查并复用；冲突时停止，不覆盖。
不导入历史、账户、视频、订阅。包含当前版本界面和抖音解析插件。
首次配置需要联网下载虚拟机基础镜像、MeTube 镜像和指定下载引擎。
TXT
  exit 0;;
 install|--backend-only|--verify-only|--check);;
 *) printf '不支持的参数：%s\n' "$mode" >&2;exit 2;;
esac
[ -f "$base/SHA256SUMS.txt" ] && [ -f "$base/runtime.env" ] && [ -d "$base/runtime" ] || fail '安装包不完整，请从 GitHub Releases 下载完整原版安装包并解压。'
(cd "$base" && /usr/bin/shasum -a 256 -c SHA256SUMS.txt >/dev/null) || fail '文件校验失败，请重新下载。'
# Manifest belongs to the checked package, not to user state.
source "$base/runtime.env"
[ "$mode" != '--verify-only' ] || { echo '安装文件校验通过。';exit 0; }
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || fail '此包只支持 Apple Silicon Mac。'
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail '需要 macOS 14 或更高版本。'
payload_app="$base/Video Extractor.app"
embedded=false
if [ "$(basename "$base")" = BackendInstaller ]; then
 payload_app="$(cd "$base/../../.." && pwd)"
 embedded=true
fi
[ -d "$payload_app" ] || fail '安装包缺少原版程序。'
/usr/bin/codesign --verify --deep --strict "$payload_app" || fail '原版程序签名完整性检查失败。'
install_home="$HOME"
export PATH="${install_home}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
bin="${install_home}/.local/bin"
profile="${install_home}/.colima/metube/colima.yaml"
cache="${install_home}/Downloads/MeTube"
app="${install_home}/Applications/Video Extractor.app"
source "$base/preflight.sh"
runtime_preflight "$base" "${install_home}" || fail '运行组件冲突，未开始安装。'
profile_preflight "$profile" || fail '后台配置冲突，未开始安装。'
if [ "$mode" = install ] && [ -e "$app" ]; then
 identifier="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true)"
 [ "$identifier" = local.felix.shouxia ] || fail '安装位置已有另一种 Video Extractor，不能覆盖。'
 if ! diff -qr "$payload_app" "$app" >/dev/null; then
  if pgrep -f '/Video Extractor.app/Contents/MacOS/Shouxia' >/dev/null; then fail '请先退出原版 Video Extractor，再安装。';fi
 fi
fi
if [ "$mode" = '--check' ]; then
 for tool in docker colima limactl lima; do
  [ -x "$bin/$tool" ] || fail "尚未安装后台运行组件：${tool}。请在应用中重新连接以自动修复。"
 done
 [ -f "$profile" ] || fail '尚未初始化 metube 环境。'
 "$bin/docker" --context colima-metube inspect metube >/dev/null || fail 'metube 容器不可用。'
 curl --fail --silent --max-time 5 -o /dev/null http://127.0.0.1:8081/history || fail '下载服务未就绪。'
 engine_check() { "$bin/docker" --context colima-metube "$@"; }
 engine_check exec metube python3 -c "$(cat "$base/backend_setup.py")" --check || fail '下载依赖或解析插件未就绪。'
 echo '程序、运行组件与下载后台检查通过；未修改环境。';exit 0
fi
printf '准备安装原版 Mac 客户端及后台运行环境。首次安装需要联网，使用 2 CPU / 2 GiB 内存。\n'
stage='准备运行组件'
lock_dir="${install_home}/Library/Application Support/Shouxia/installer-state/setup.lock"
installer_lock "$lock_dir" || fail '后台正在准备，请稍后重新连接。'
trap 'code=$?; installer_unlock "$lock_dir"; if [ "$code" -ne 0 ]; then printf "安装停止：%s失败。检查网络后在应用中重新连接即可重试；详细信息见 backend.log。\n" "$stage" >&2; fi' EXIT
echo '进度：正在准备下载组件'
while IFS= read -r relative; do
 target="${install_home}/.local/$relative"
 if [ ! -e "$target" ] && [ ! -L "$target" ]; then
  mkdir -p "$(dirname "$target")";cp -p "$base/runtime/$relative" "$target"
 fi
done < "$base/runtime-files.txt"
for tool in docker colima limactl lima; do
 [ -x "$bin/$tool" ] || fail "安装包缺少必需组件：${tool}。请下载完整的新版本。"
done
stage='启动本机虚拟机'
echo '进度：正在启动本机下载环境（首次需要下载镜像）'
if [ -f "$profile" ];then
 "$bin/colima" start --profile metube
else
 "$bin/colima" start --profile metube --cpu 2 --memory 2 --disk 20 --arch aarch64 --runtime docker --vm-type vz --mount-type virtiofs
fi
engine(){ "$bin/docker" --context colima-metube "$@"; }
journal_dir="${install_home}/Library/Application Support/Shouxia/installer-state"
pending="$journal_dir/backend-init.pending"
complete="$journal_dir/backend-init.complete"
needs_init=false
if engine inspect metube >/dev/null 2>&1; then
 # Existing history belongs to this user; do not copy, update or recreate it.
 ports="$(engine inspect metube --format '{{range (index .HostConfig.PortBindings "8081/tcp")}}{{.HostIp}}:{{.HostPort}}{{end}}')"
 mount="$(engine inspect metube --format '{{range .Mounts}}{{if eq .Destination "/downloads"}}{{.Source}}{{end}}{{end}}')"
 [ "$ports" = '127.0.0.1:8081' ] && [ "$mount" = "$cache" ] || fail '已有 metube 容器的端口或下载目录与原版不匹配；安装不会修改容器。'
 container_id="$(engine inspect metube --format '{{.Id}}')"
 owner="$(engine inspect metube --format '{{index .Config.Labels "com.video-extractor.native-installer"}}')"
 if [ -f "$pending" ];then
  [ "$owner" = 1.0.0 ] && init_journal_matches "$pending" "$container_id" || fail '后台初始化记录与当前容器不符；为保护数据，不会继续修改。'
  needs_init=true
 elif [ "$owner" = 1.0.0 ];then
  init_journal_matches "$complete" "$container_id" || fail '此安装器创建的后台缺少初始化完成记录，不能当作完整环境复用。请联系维护者。'
 fi
 engine start metube >/dev/null
else
 if /usr/sbin/lsof -nP -iTCP:8081 -sTCP:LISTEN >/dev/null 2>&1;then fail '8081 端口被其他服务占用，未创建容器。';fi
 mkdir -p "$cache"
 stage='下载 MeTube 镜像'
 echo '进度：正在下载 MeTube 后台（首次需联网，可能需要几分钟）'
 pulled=false
 for attempt in 1 2 3; do
  if engine pull "$METUBE_IMAGE"; then pulled=true;break;fi
  sleep "$attempt"
 done
 [ "$pulled" = true ] || fail 'MeTube 镜像下载失败；检查网络后重新连接，已下载的镜像层会复用。'
 container_id="$(engine create --name metube --label com.video-extractor.native-installer=1.0.0 --restart unless-stopped -p 127.0.0.1:8081:8081 -v "$cache:/downloads" -e DOWNLOAD_DIR=/downloads -e STATE_DIR=/downloads/.metube -e TEMP_DIR=/downloads -e ALLOW_YTDL_OPTIONS_OVERRIDES=true -e MAX_CONCURRENT_DOWNLOADS=2 -e PUID=1000 -e PGID=1000 -e UMASK=022 "$METUBE_IMAGE")"
 mkdir -p "$journal_dir";chmod 700 "$journal_dir"
 printf '%s\n' "$container_id" > "$pending.tmp";mv "$pending.tmp" "$pending"
 needs_init=true
 engine start metube >/dev/null
fi
if [ "$needs_init" = true ];then
 stage='安装下载引擎'
 echo '进度：正在安装下载引擎'
 # A journal keyed to the created container allows safe retry after interruption.
 engine exec --user 0 metube python3 -m pip install --retries 3 --timeout 30 --no-cache-dir --no-deps --index-url https://pypi.org/simple "yt-dlp==$YTDLP_PACKAGE_VERSION"
 current="$(engine exec metube python3 -c 'import yt_dlp.version;print(yt_dlp.version.__version__)')"
 [ "$current" = "$YTDLP_RUNTIME_VERSION" ] || fail '下载引擎版本验证失败，未安装客户端。请保留终端错误信息。'
 engine restart metube >/dev/null
 printf '%s\n' "$container_id" > "$complete.tmp";mv "$complete.tmp" "$complete"
 # Moving the pending file into a completed journal retains recovery evidence.
 mv "$pending" "$journal_dir/backend-init.last"
fi
ready=false
stage='检查下载服务'
echo '进度：正在检查下载服务和解析插件'
for attempt in {1..30};do
 if curl --fail --silent --max-time 2 -o /dev/null http://127.0.0.1:8081/history;then ready=true;break;fi
 sleep 1
done
[ "$ready" = true ] || fail '下载后台未就绪，未安装客户端。请保留终端错误信息。'
# Deploy the same extractor shipped with this source release. No account data is copied.
plugin="$base/BackendPlugins/yt_dlp_plugins/extractor/shouxia_douyin.py"
[ -f "$plugin" ] || fail '安装包缺少抖音解析插件。'
plugin_hash="$(/usr/bin/shasum -a 256 "$plugin" | awk '{print $1}')"
plugin_state="$(engine exec -i --user 0 metube python3 -c "$(cat "$base/backend_setup.py")" --install "$plugin_hash" < "$plugin")" || fail '解析插件准备失败，客户端尚未更新。请完成后台任务后重试。'
if [ "$plugin_state" = changed ];then
 engine restart metube >/dev/null
 ready=false
 for attempt in {1..30};do
  if curl --fail --silent --max-time 2 -o /dev/null http://127.0.0.1:8081/history;then ready=true;break;fi
  sleep 1
 done
 [ "$ready" = true ] || fail '后台重新连接失败，客户端尚未更新；再次运行可恢复。'
fi
engine exec --user 0 metube python3 -c "$(cat "$base/backend_setup.py")" --activate || fail '下载依赖检查失败。'
if [ "$mode" = '--backend-only' ]; then
 echo '下载后台已就绪。'
 exit 0
fi
# Embedded installers are used by the running app and never copy/open another app.
[ "$embedded" = false ] || { echo '下载后台已就绪。';exit 0; }
stage='安装客户端'
mkdir -p "${install_home}/Applications"
if [ ! -d "$app" ] || ! diff -qr "$payload_app" "$app" >/dev/null;then
 if [ -d "$app" ];then
  backup="${install_home}/Library/Application Support/Shouxia/installer-backups/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup";ditto -c -k --keepParent "$app" "$backup/Video-Extractor-backup.zip"
 fi
 ditto "$payload_app" "$app"
fi
/usr/bin/codesign --verify --deep --strict "$app"
echo '安装完成。打开软件后粘贴链接即可开始提取。'
open "$app"
