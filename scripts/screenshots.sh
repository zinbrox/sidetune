#!/bin/zsh
# Renders README screenshots and docs/demo.gif from the real views (see Tests/Showcase).
set -euo pipefail
ROOT="${0:A:h:h}"
OUT="$ROOT/docs"
mkdir -p "$OUT" "$ROOT/build"
# Album covers for the showcase tracks, from Apple's public iTunes catalog.
ART="$ROOT/build/showcase-art"
mkdir -p "$ART"
typeset -A COVERS=(
  californication.jpg "https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/07/87/66/078766a8-41b3-3e62-53ef-c30cf8f03e50/093624932130.jpg/1200x1200bb.jpg"
  everywhere.jpg "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/a3/71/ee/a371eea6-b148-0e47-9170-baf2147c8f7b/603497870066.jpg/1200x1200bb.jpg"
  sevennation.jpg "https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/07/25/09/0725098a-09f4-f240-e551-94384a590371/886448799009.jpg/1200x1200bb.jpg"
)
for file url in "${(@kv)COVERS}"; do
  [[ -f "$ART/$file" ]] || curl -fsSL -o "$ART/$file" "$url" || echo "couldn't fetch $file; using generated art"
done

SOURCES=("${(@f)$(find "$ROOT/Sources/SideTune" -name '*.swift' ! -name main.swift | sort)}")
"$ROOT/scripts/swiftc.sh" -D PREVIEW -swift-version 5 -target "$(uname -m)-apple-macos14" -module-name SideTune \
  "${SOURCES[@]}" "$ROOT/Tests/Showcase/main.swift" -o "$ROOT/build/SideTuneShowcase"
"$ROOT/build/SideTuneShowcase" "$OUT" "${SLOWDOWN:-6}" "$ART"

# GIF: frames play back at the measured rate (capped at 30 fps; GIF delays are in centiseconds).
FPS=$(cat "$OUT/demo-fps.txt")
ffmpeg -loglevel error -y -framerate "$FPS" -i "$OUT/demo-frames/f%04d.png" \
  -vf "fps=30,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
  "$OUT/demo.gif"
rm -rf "$OUT/demo-frames" "$OUT/demo-fps.txt"

# App icon for the README header.
cp "$ROOT/build/AppIcon.iconset/icon_256x256@2x.png" "$OUT/icon.png"
echo "✓ $OUT"
