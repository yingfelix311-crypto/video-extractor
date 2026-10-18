#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
fixtures=$(mktemp -d "${TMPDIR:-/tmp}/clip-canvases.XXXXXX")
trap 'rm -rf "$fixtures"' EXIT
ffmpeg -v error -f lavfi -i color=c=red:s=640x360:r=30:d=4 -f lavfi -i sine=frequency=440:duration=4 -vf "drawbox=x=iw/2:y=0:w=iw/2:h=ih/2:color=lime:t=fill,drawbox=x=0:y=ih/2:w=iw/2:h=ih/2:color=blue:t=fill,drawbox=x=iw/2:y=ih/2:w=iw/2:h=ih/2:color=yellow:t=fill,drawbox=x=0:y=0:w=iw:h=ih:color=white:t=12" -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$fixtures/landscape.mp4"
ffmpeg -v error -i "$fixtures/landscape.mp4" -c copy -metadata:s:v:0 rotate=90 "$fixtures/rotated.mp4"
ffmpeg -v error -f lavfi -i color=c=red:s=360x640:r=30:d=4 -f lavfi -i sine=frequency=440:duration=4 -vf "drawbox=x=iw/2:y=0:w=iw/2:h=ih/2:color=lime:t=fill,drawbox=x=0:y=ih/2:w=iw/2:h=ih/2:color=blue:t=fill,drawbox=x=iw/2:y=ih/2:w=iw/2:h=ih/2:color=yellow:t=fill,drawbox=x=0:y=0:w=iw:h=ih:color=white:t=12" -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$fixtures/portrait.mp4"
bash test-clips.sh "$fixtures/landscape.mp4" --fixture
.build/clip-tests "$fixtures/portrait.mp4" --fixture
.build/clip-tests "$fixtures/rotated.mp4" --fixture
