#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE_ROOT="$(pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
PROJECT="$CHECK_DIR/project"
mkdir -p "$PROJECT/scripts"
cp Package.swift "$PROJECT/Package.swift"
cp -R Sources Resources "$PROJECT/"
cp scripts/build.sh "$PROJECT/scripts/build.sh"
(cd "$PROJECT" && FOLD_MENU_SIGNING_IDENTITY=- bash scripts/build.sh)

APP="$PROJECT/dist/Fold Menu.app"
ICON="$APP/Contents/Resources/AppIcon.icns"

test "$(plutil -extract CFBundleIconFile raw -o - "$APP/Contents/Info.plist")" = "AppIcon"
test -s "$ICON"

iconutil --convert iconset --output "$CHECK_DIR/AppIcon.iconset" "$ICON"
test -s "$CHECK_DIR/AppIcon.iconset/icon_512x512@2x.png"

test "$(sips -g pixelWidth "$SOURCE_ROOT/Resources/AppIcon.png" | awk '/pixelWidth:/ {print $2}')" = "1024"
test "$(sips -g pixelHeight "$SOURCE_ROOT/Resources/AppIcon.png" | awk '/pixelHeight:/ {print $2}')" = "1024"
test "$(sips -g pixelWidth "$SOURCE_ROOT/Resources/GitHubPreview.png" | awk '/pixelWidth:/ {print $2}')" = "1200"
test "$(sips -g pixelHeight "$SOURCE_ROOT/Resources/GitHubPreview.png" | awk '/pixelHeight:/ {print $2}')" = "630"

printf '%s\n' 'Brand assets are packaged at the expected sizes.'
