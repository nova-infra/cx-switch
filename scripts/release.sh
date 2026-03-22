#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  cat <<'EOF'
Usage: scripts/release.sh <version> [dmg-path]

Examples:
  scripts/release.sh 0.1.0
  scripts/release.sh 0.1.0 .build/releases/CXSwitch.dmg
EOF
  exit 1
fi

VERSION="$1"
DMG_PATH="${2:-.build/releases/CXSwitch-${VERSION}.dmg}"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
APPCAST_PATH="docs/appcast.xml"
DMG_BASENAME="$(basename "$DMG_PATH")"
RELEASE_URL="https://github.com/nova-infra/cx-switch/releases/download/v${VERSION}/${DMG_BASENAME}"
swift build -c release
BUILD_DIR="$(swift build -c release --show-bin-path)"
APP_NAME="CXSwitch"
APP_DIR=".build/releases/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "CXSwitch/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "CXSwitch/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp -R "$BUILD_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/"

codesign --force --deep --sign - "$APP_DIR"

mkdir -p "$(dirname "$DMG_PATH")"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH"

SIGNATURE_OUTPUT="$("$SPARKLE_BIN/sign_update" -p "$DMG_PATH")"
DMG_LENGTH="$(stat -f %z "$DMG_PATH")"

cat <<EOF
Version: $VERSION
App bundle: $APP_DIR
DMG: $DMG_PATH

Appcast enclosure:
  <enclosure url="$RELEASE_URL" sparkle:edSignature="$SIGNATURE_OUTPUT" length="$DMG_LENGTH" type="application/octet-stream" />

Update the appcast item in $APPCAST_PATH with this enclosure and the release notes.
EOF
