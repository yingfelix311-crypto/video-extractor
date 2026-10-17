#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
docker_cli="${SHOUXIA_DOCKER:-$HOME/.local/bin/docker}"
docker_context="${SHOUXIA_DOCKER_CONTEXT:-colima-metube}"
plugin_dir='/downloads/.shouxia/yt-dlp-plugins'

# The existing engine and curl_cffi are prerequisites; no package downloads.
"$docker_cli" --context "$docker_context" exec metube python3 -c '
from pathlib import Path
from yt_dlp import YoutubeDL
from yt_dlp.networking.impersonate import ImpersonateTarget
assert YoutubeDL({"quiet": True})._impersonate_target_available(
    ImpersonateTarget.from_str("chrome-131:android-14")), "Chrome Android target unavailable"
root=Path("/downloads/.shouxia/yt-dlp-plugins")
(root/"yt_dlp_plugins/extractor").mkdir(parents=True, exist_ok=True)
target=Path("/etc/yt-dlp/plugins/shouxia")
target.parent.mkdir(parents=True, exist_ok=True)
assert not (target.exists() or target.is_symlink()) or (target.is_symlink() and target.resolve()==root), "Existing plugin path is owned elsewhere"
source=root/"yt_dlp_plugins/extractor/shouxia_douyin.py"
if source.exists():
    from datetime import datetime
    backup=root.parent/"plugin-backups"/datetime.now().strftime("%Y%m%d-%H%M%S")
    backup.mkdir(parents=True, exist_ok=False)
    (backup/source.name).write_bytes(source.read_bytes())
'
"$docker_cli" --context "$docker_context" cp \
  BackendPlugins/yt_dlp_plugins/extractor/shouxia_douyin.py \
  "metube:$plugin_dir/yt_dlp_plugins/extractor/shouxia_douyin.py"
"$docker_cli" --context "$docker_context" exec metube python3 -c '
from pathlib import Path
target=Path("/etc/yt-dlp/plugins/shouxia")
if not target.is_symlink(): target.symlink_to("/downloads/.shouxia/yt-dlp-plugins", target_is_directory=True)
from yt_dlp import YoutubeDL
extractor=YoutubeDL({"quiet":True}).get_info_extractor("Douyin")
assert extractor._real_extract.__module__.endswith("shouxia_douyin"), "Plugin did not load"
print("Douyin mobile-share fallback installed. Restart idle metube to load it in the service.")
'
