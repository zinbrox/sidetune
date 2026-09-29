#!/bin/zsh
# swiftc wrapper. Some Command Line Tools installs ship both module.modulemap and
# bridging.modulemap defining `SwiftBridging`, which breaks every Swift compile.
# When that's the case, hide the duplicate through a VFS overlay instead of touching system files.
set -euo pipefail

ROOT="${0:A:h:h}"
INC="$(dirname "$(xcrun --find swiftc)")/../include/swift"
FLAGS=()
if [[ -f "$INC/module.modulemap" && -f "$INC/bridging.modulemap" ]]; then
  CACHE="$ROOT/build/.toolchain"
  mkdir -p "$CACHE"
  : > "$CACHE/empty.modulemap"
  REAL="$(cd "$INC" && pwd -P)/bridging.modulemap"
  cat > "$CACHE/overlay.yaml" <<EOF
{ "version": 0, "case-sensitive": "false", "roots": [
  { "type": "file", "name": "$REAL", "external-contents": "$CACHE/empty.modulemap" } ] }
EOF
  FLAGS=(-vfsoverlay "$CACHE/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$CACHE/overlay.yaml")
fi

exec xcrun swiftc "${FLAGS[@]}" "$@"
