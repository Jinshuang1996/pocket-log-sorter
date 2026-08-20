#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
OUTPUT_DIR=${POCKET_SORTER_OUTPUT_DIR:-"$SCRIPT_DIR/dist"}
APP_DIR="$OUTPUT_DIR/Pocket色彩分拣器.app"
BUILD_ROOT=$(mktemp -d)
trap 'rm -rf "$BUILD_ROOT"' EXIT
STAGED_APP="$BUILD_ROOT/Pocket色彩分拣器.app"
CONTENTS="$STAGED_APP/Contents"
ICONSET="$BUILD_ROOT/AppIcon.iconset"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
mkdir -p "$ICONSET"

for ARCH in arm64 x86_64; do
  xcrun swiftc \
    -parse-as-library \
    -Onone \
    -target "$ARCH-apple-macos13.0" \
    -framework SwiftUI \
    -framework AppKit \
    -framework AVFoundation \
    -framework AVKit \
    -framework UniformTypeIdentifiers \
    "$SCRIPT_DIR/PocketColorSorter.swift" \
    "$SCRIPT_DIR/DjiMetadataReader.swift" \
    -o "$BUILD_ROOT/PocketColorSorter-$ARCH"
done

lipo -create \
  "$BUILD_ROOT/PocketColorSorter-arm64" \
  "$BUILD_ROOT/PocketColorSorter-x86_64" \
  -output "$CONTENTS/MacOS/PocketColorSorter"

sips -z 16 16 "$SCRIPT_DIR/assets/AppIcon-master.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$SCRIPT_DIR/assets/AppIcon-master.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SCRIPT_DIR/assets/AppIcon-master.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$SCRIPT_DIR/assets/AppIcon-master.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SCRIPT_DIR/assets/AppIcon-master.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$SCRIPT_DIR/assets/AppIcon-master.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SCRIPT_DIR/assets/AppIcon-master.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$SCRIPT_DIR/assets/AppIcon-master.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SCRIPT_DIR/assets/AppIcon-master.png" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SCRIPT_DIR/assets/AppIcon-master.png" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

cp "$SCRIPT_DIR/Info.plist" "$CONTENTS/Info.plist"
cp "$SCRIPT_DIR/THIRD_PARTY_NOTICES.txt" "$CONTENTS/Resources/THIRD_PARTY_NOTICES.txt"
xattr -cr "$STAGED_APP"
codesign --force --deep --sign - "$STAGED_APP"
rm -rf "$APP_DIR"
ditto "$STAGED_APP" "$APP_DIR"
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
codesign --verify --deep --strict "$APP_DIR"
echo "$APP_DIR"
