#!/bin/zsh
# Renders overlay states to build/preview/*.png with sample data.
set -euo pipefail
ROOT="${0:A:h:h}"
OUT="$ROOT/build/preview"
mkdir -p "$OUT"
SOURCES=("${(@f)$(find "$ROOT/Sources/SideTune" -name '*.swift' ! -name main.swift | sort)}")
"$ROOT/scripts/swiftc.sh" -D PREVIEW -swift-version 5 -target "$(uname -m)-apple-macos14" -module-name SideTune \
  "${SOURCES[@]}" "$ROOT/Tests/Preview/main.swift" -o "$ROOT/build/SideTunePreview"
"$ROOT/build/SideTunePreview" "$OUT" "${1:-$ROOT/build/AppIcon.iconset/icon_256x256@2x.png}"
echo "✓ $OUT"
