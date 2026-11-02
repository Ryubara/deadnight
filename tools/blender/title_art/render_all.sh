#!/usr/bin/env bash
# Renders the title art masters with the pinned Blender, headless. Usage:
#   BLENDER="$(gds tool path blender)" render_all.sh <out dir> <land width> <port width> <samples> [shots...]
# Draft: render_all.sh <dir> 960 480 24      Final: render_all.sh <dir> 3840 2400 128
# Videos (Discord preview frames): VIDEO=<frames> VIDEO_W=<width> render_all.sh <dir> 0 0 <samples> [shots...]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
B="${BLENDER:?set BLENDER to the pinned Blender: gds tool path blender}"
OUT="$1"; LW="$2"; PW="$3"; SAMPLES="$4"; shift 4
SHOTS="${*:-feature headlights marquee headliner backtoback}"
mkdir -p "$OUT"
for shot in $SHOTS; do
  if [[ "${VIDEO:-}" != "" ]]; then
    start=$(date +%s)
    timeout 5400 "$B" -b --factory-startup -P "$HERE/title_shots.py" -- --shot "$shot" --width "${VIDEO_W:-640}" \
      --samples "$SAMPLES" --frames "$VIDEO" --push "${PUSH:-1.2}" --video-dir "$OUT/video_${shot}_${VIDEO_W:-640}" 2>&1 \
      | grep -E "Error|Traceback|wrote" || true
    echo "$shot video ${VIDEO} frames: $(( $(date +%s) - start )) s"
    continue
  fi
  for aspect in land port; do
    W=$LW; [[ $aspect == port ]] && W=$PW
    [[ $W == 0 ]] && continue
    start=$(date +%s)
    timeout 3600 "$B" -b --factory-startup -P "$HERE/title_shots.py" -- --shot "$shot" --aspect "$aspect" \
      --width "$W" --samples "$SAMPLES" --out "$OUT/${shot}_${aspect}.png" 2>&1 | grep -E "Error|Traceback|wrote" || true
    echo "$shot $aspect ${W} ${SAMPLES} samples: $(( $(date +%s) - start )) s"
  done
done
