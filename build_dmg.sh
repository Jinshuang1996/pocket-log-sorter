#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
OUTPUT_DIR=${POCKET_SORTER_OUTPUT_DIR:-"$SCRIPT_DIR/dist"}
APP_DIR="$OUTPUT_DIR/Pocket色彩分拣器.app"
DMG_PATH="$OUTPUT_DIR/Pocket色彩分拣器-通用版.dmg"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

"$SCRIPT_DIR/build.sh"
xattr -cr "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
ditto --norsrc "$APP_DIR" "$STAGING/Pocket色彩分拣器.app"
cp "$SCRIPT_DIR/安装说明.txt" "$STAGING/安装说明.txt"
ln -s /Applications "$STAGING/应用程序"

hdiutil create \
  -volname "Pocket 色彩分拣器" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
