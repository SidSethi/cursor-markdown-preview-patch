#!/usr/bin/env bash
# Regenerate assets/preview-demo.gif from the real preview CSS/JS demo fixture.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HTML_PATH="$SCRIPT_DIR/readme-demo.html"
OUTPUT_PATH="$SCRIPT_DIR/assets/preview-demo.gif"
CHROME_BIN="${CHROME_BIN:-}"

if [[ -z "$CHROME_BIN" ]]; then
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "google-chrome" \
    "chromium"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      CHROME_BIN="$(command -v "$candidate")"
      break
    fi
    if [[ -x "$candidate" ]]; then
      CHROME_BIN="$candidate"
      break
    fi
  done
fi

[[ -n "$CHROME_BIN" ]] || { echo "error: Chrome or Chromium not found" >&2; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo "error: ffmpeg not found" >&2; exit 1; }

mkdir -p "$(dirname "$OUTPUT_PATH")"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT

for frame in $(seq 0 47); do
  frame_name="$(printf 'frame-%03d.png' "$frame")"
  "$CHROME_BIN" \
    --headless=new \
    --disable-gpu \
    --hide-scrollbars \
    --allow-file-access-from-files \
    --force-device-scale-factor=1 \
    --window-size=1200,675 \
    --virtual-time-budget=1000 \
    --screenshot="$tmp/$frame_name" \
    "file://$HTML_PATH?frame=$frame" \
    >/dev/null 2>&1
done

ffmpeg \
  -hide_banner \
  -loglevel error \
  -y \
  -framerate 6 \
  -i "$tmp/frame-%03d.png" \
  -filter_complex \
    "fps=6,scale=960:-1:flags=lanczos,split[frames][palette_source];[palette_source]palettegen=max_colors=128:stats_mode=diff[palette];[frames][palette]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
  -loop 0 \
  "$OUTPUT_PATH"

echo "wrote $OUTPUT_PATH"
