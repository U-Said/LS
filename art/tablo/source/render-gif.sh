#!/usr/bin/env bash
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
target=${1:-"$src/../FastRevers-Tablo-FR.gif"}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

node "$src/render-gif.mjs" prepare "$work"
size=$(cat "$work/size.txt")
if [[ -f "$work/fonts.conf" ]]; then export FONTCONFIG_FILE="$work/fonts.conf"; fi
while IFS= read -r pair; do
  inkscape "$work/$pair.svg" --export-area-page --export-width="$((size * 2))" --export-filename="$work/$pair.png"
  ffmpeg -nostdin -v error -i "$work/$pair.png" -vf "scale=$size:$size:flags=lanczos" -frames:v 1 \
    -pix_fmt rgba -f rawvideo -threads 1 "$work/$pair.rgba"
done < "$work/pairs.txt"

node "$src/render-gif.mjs" frames "$work"
ffmpeg -nostdin -v error -f rawvideo -pixel_format rgba -video_size "${size}x${size}" -framerate 25 \
  -i "$work/frames.rgba" -filter_complex_threads 1 -filter_complex \
  '[0:v]split[a][b];[a]palettegen=stats_mode=full:reserve_transparent=1[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:alpha_threshold=128' \
  -loop 0 -gifflags +offsetting+transdiff "$work/animation.gif"
node "$src/render-gif.mjs" finish "$work" "$target"
