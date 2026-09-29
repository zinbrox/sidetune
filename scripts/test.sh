#!/bin/zsh
# Compiles the pure-logic sources with Tests/main.swift and runs them.
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build"
"$ROOT/scripts/swiftc.sh" -swift-version 5 -target "$(uname -m)-apple-macos14" \
  "$ROOT/Sources/SideTune/Window/EdgeSnapper.swift" \
  "$ROOT/Sources/SideTune/Media/NowPlaying.swift" \
  "$ROOT/Sources/SideTune/Media/RouterLogic.swift" \
  "$ROOT/Tests/main.swift" \
  -o "$ROOT/build/SideTuneTests"
"$ROOT/build/SideTuneTests"
