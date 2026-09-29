#!/bin/zsh
# Builds build/SideTune.app without Xcode: mediaremote-adapter via CMake, the app via swiftc.
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build"
APP="$BUILD/SideTune.app"
ADAPTER="$ROOT/Vendor/mediaremote-adapter"
CONFIG="${1:-release}"
ARCH="$(uname -m)"

mkdir -p "$BUILD"

# 1. Adapter framework (lets us read now playing from any app on macOS 15.4+).
if [[ ! -d "$ADAPTER/build/MediaRemoteAdapter.framework" ]]; then
  echo "› Building mediaremote-adapter"
  command -v cmake >/dev/null || { echo "cmake is required: brew install cmake"; exit 1; }
  cmake -S "$ADAPTER" -B "$ADAPTER/build" -DCMAKE_BUILD_TYPE=Release >/dev/null
  cmake --build "$ADAPTER/build" >/dev/null
fi

# 2. App icon.
if [[ ! -f "$BUILD/AppIcon.icns" || "$ROOT/scripts/make-icon.swift" -nt "$BUILD/AppIcon.icns" ]]; then
  echo "› Rendering app icon"
  "$ROOT/scripts/swiftc.sh" -swift-version 5 -target "$ARCH-apple-macos14" "$ROOT/scripts/make-icon.swift" -o "$BUILD/make-icon"
  rm -rf "$BUILD/AppIcon.iconset"
  "$BUILD/make-icon" "$BUILD/AppIcon.iconset"
  iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"
fi

# 3. App binary.
echo "› Compiling SideTune ($CONFIG)"
OPT=(-O)
[[ "$CONFIG" == "debug" ]] && OPT=(-Onone -g)
SOURCES=("${(@f)$(find "$ROOT/Sources/SideTune" -name '*.swift' | sort)}")
"$ROOT/scripts/swiftc.sh" "${OPT[@]}" -swift-version 5 -target "$ARCH-apple-macos14" \
  -module-name SideTune "${SOURCES[@]}" -o "$BUILD/SideTune"

# 4. Bundle.
echo "› Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/SideTune" "$APP/Contents/MacOS/SideTune"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ADAPTER/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp -R "$ADAPTER/build/MediaRemoteAdapter.framework" "$APP/Contents/Resources/"

# 5. Ad-hoc sign (inside-out) so macOS will run it and remember Automation permission.
codesign --force --sign - "$APP/Contents/Resources/MediaRemoteAdapter.framework" >/dev/null
codesign --force --sign - --identifier com.zinbrox.SideTune "$APP" >/dev/null

echo "✓ $APP"
