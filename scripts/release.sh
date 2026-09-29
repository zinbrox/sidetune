#!/bin/zsh
# Builds release artifacts into dist/: universal app as .dmg and .zip, a source .zip,
# SHA-256 checksums and release notes. Doesn't touch git.
#   scripts/release.sh 1.0.0
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${1:?usage: scripts/release.sh VERSION}"
DIST="$ROOT/dist"
NAME="SideTune-$VERSION"
APP="$ROOT/build/SideTune.app"

rm -rf "$DIST"
mkdir -p "$DIST"

# 1. Universal (Apple Silicon + Intel) app with the version stamped in.
VERSION="$VERSION" ARCHS="arm64 x86_64" "$ROOT/scripts/build-app.sh" release

# 2. Zip of the app (ditto keeps bundle metadata and signatures intact).
echo "› Zipping app"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$NAME.zip"

# 3. Disk image: the app next to an Applications shortcut, with the app icon on the volume.
echo "› Building disk image"
STAGE="$ROOT/build/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/build/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
hdiutil create -quiet -volname "SideTune" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$ROOT/build/rw.dmg"
MOUNT=$(hdiutil attach -nobrowse -noautoopen "$ROOT/build/rw.dmg" | awk -F'\t' '/\/Volumes\//{print $NF}')
SetFile -a C "$MOUNT" 2>/dev/null || true # custom volume icon flag (needs Command Line Tools)
hdiutil detach -quiet "$MOUNT"
hdiutil convert -quiet "$ROOT/build/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DIST/$NAME.dmg"
rm -f "$ROOT/build/rw.dmg"
rm -rf "$STAGE"

# 4. Source archive (what GitHub's "Source code (zip)" would contain, minus build output).
echo "› Archiving source"
SRC="$ROOT/build/source/$NAME-source"
rm -rf "$ROOT/build/source"
mkdir -p "$SRC"
rsync -a \
  --exclude '.git' --exclude '.DS_Store' --exclude '/build' --exclude '/dist' \
  --exclude 'Vendor/mediaremote-adapter/build' --exclude '.claude' \
  "$ROOT/" "$SRC/"
(cd "$ROOT/build/source" && zip -qry "$DIST/$NAME-source.zip" "$NAME-source")
rm -rf "$ROOT/build/source"

# 5. Checksums and notes.
(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" "$NAME-source.zip" > SHA256SUMS.txt)
sed "s/{{VERSION}}/$VERSION/g" "$ROOT/scripts/release-notes.md" > "$DIST/RELEASE_NOTES.md"

echo "✓ $DIST"
ls -lh "$DIST"
