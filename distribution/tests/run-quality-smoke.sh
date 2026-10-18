#!/bin/bash
# Integration fixture: a disposable, unpublished service and local synthetic media.
set -euo pipefail
cd "$(dirname "$0")/../.."
source distribution/macos/runtime.env
docker_cli="${SHOUXIA_DOCKER:-$HOME/.local/bin/docker}"
container="ve-quality-smoke-$$"
cleanup(){ "$docker_cli" --context colima-metube rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
# Private addresses are allowed only inside this disposable fixture so it can fetch
# the synthetic local HLS server. The production service keeps its normal guard.
"$docker_cli" --context colima-metube run -d --name "$container" --tmpfs /downloads:rw,size=256m \
 -e DOWNLOAD_DIR=/downloads -e STATE_DIR=/downloads/.state \
 -e ALLOW_YTDL_OPTIONS_OVERRIDES=true -e ALLOW_PRIVATE_ADDRESSES=true "$METUBE_IMAGE" >/dev/null
"$docker_cli" --context colima-metube cp distribution/tests/quality_smoke.py "$container:/tmp/quality-smoke.py"
"$docker_cli" --context colima-metube exec "$container" python3 /tmp/quality-smoke.py
