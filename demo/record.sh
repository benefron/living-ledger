#!/usr/bin/env bash
# Records demo/demo.gif:  brew install vhs && bash demo/record.sh
# vhs renders the terminal frames; ffmpeg assembles the GIF here directly, because vhs 0.12
# silently produces nothing when it drives ffmpeg 9 itself.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
rm -rf demo/frames
vhs demo/demo.tape >/dev/null
ffmpeg -hide_banner -loglevel error -y \
  -framerate 25 -i demo/frames/frame-text-%05d.png \
  -framerate 25 -i demo/frames/frame-cursor-%05d.png \
  -filter_complex "[0:v][1:v]overlay=format=auto,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:diff_mode=rectangle" \
  -loop 0 demo/demo.gif
rm -rf demo/frames
ls -la demo/demo.gif
