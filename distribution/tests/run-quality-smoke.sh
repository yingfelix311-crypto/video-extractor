#!/bin/bash
# Integration fixture: a disposable, unpublished service and local synthetic media.
set -euo pipefail
cd "$(dirname "$0")/../.."
source distribution/macos/runtime.env
docker_cli="${SHOUXIA_DOCKER:-$HOME/.local/bin/docker}"
container="ve-quality-smoke-$$"
cleanup(){ "$docker_cli" --context colima-metube rm -fv "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
# Private addresses are allowed only inside this disposable fixture so it can fetch
# the synthetic local HLS server. The production service keeps its normal guard.
"$docker_cli" --context colima-metube run -d --name "$container" --mount type=volume,destination=/downloads \
 -e DOWNLOAD_DIR=/downloads -e STATE_DIR=/downloads/.state \
 -e ALLOW_YTDL_OPTIONS_OVERRIDES=true -e ALLOW_PRIVATE_ADDRESSES=true "$METUBE_IMAGE" >/dev/null
engine(){ "$docker_cli" --context colima-metube "$@"; }
engine exec --user 0 "$container" python3 -m pip install --quiet --root-user-action=ignore --no-cache-dir --no-deps --index-url https://pypi.org/simple "yt-dlp==$YTDLP_PACKAGE_VERSION"
wait_ready(){
 engine exec "$container" python3 -c 'import time,urllib.request
for attempt in range(30):
 try:
  urllib.request.urlopen("http://127.0.0.1:8081/history",timeout=2).close();break
 except Exception:time.sleep(1)
else:raise SystemExit("test backend did not start")'
}
wait_ready
plugin=Shouxia/BackendPlugins/yt_dlp_plugins/extractor/shouxia_douyin.py
plugin_hash="$(/usr/bin/shasum -a 256 "$plugin" | awk '{print $1}')"
engine exec -i --user 0 "$container" python3 -c "$(cat distribution/macos/backend_setup.py)" --install "$plugin_hash" < "$plugin"
engine restart "$container" >/dev/null
wait_ready
engine exec --user 0 "$container" python3 -c "$(cat distribution/macos/backend_setup.py)" --activate
"$docker_cli" --context colima-metube cp distribution/tests/quality_smoke.py "$container:/tmp/quality-smoke.py"
"$docker_cli" --context colima-metube exec "$container" python3 /tmp/quality-smoke.py
