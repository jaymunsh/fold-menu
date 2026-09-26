#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$(pwd)/dist/Fold Menu.app"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp .build/release/FoldMenu "$APP/Contents/MacOS/FoldMenu"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
SIGNING_IDENTITY="${FOLD_MENU_SIGNING_IDENTITY:--}"
if [ "$SIGNING_IDENTITY" = "-" ] && [ -f .local-signing/fold-menu.keychain-db ]; then
  SIGNING_KEYCHAIN="$(pwd)/.local-signing/fold-menu.keychain-db"
  SIGNING_PASSWORD="$(<.local-signing/password)"
  security unlock-keychain -p "$SIGNING_PASSWORD" "$SIGNING_KEYCHAIN"
  ORIGINAL_KEYCHAINS=()
  while IFS= read -r entry; do
    entry="${entry#*\"}"
    entry="${entry%\"*}"
    ORIGINAL_KEYCHAINS+=("$entry")
  done < <(security list-keychains -d user)
  trap 'security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}"' EXIT
  security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" "$SIGNING_KEYCHAIN"
  SIGNING_IDENTITY="Fold Menu Local Development"
  codesign --force --sign "$SIGNING_IDENTITY" --keychain "$SIGNING_KEYCHAIN" "$APP"
else
  codesign --force --sign "$SIGNING_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
if [ "$SIGNING_IDENTITY" = "-" ]; then
  printf '%s\n' 'Development build: ad-hoc signing. Rebuilds may invalidate Accessibility permission.'
  printf '%s\n' 'Set FOLD_MENU_SIGNING_IDENTITY to a persistent code-signing identity for stable permissions.'
fi
printf 'Built: %s\n' "$APP"
