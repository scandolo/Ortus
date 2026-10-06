#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Local builds use ad-hoc signing: no keychain import, password, or trust dialog.
# Website blocking uses a Native Messaging companion, not signature-bound TCC.
SIGNING_IDENTITY="${ORTUS_SIGNING_IDENTITY:--}"
MODE="${1:-debug}"
CONFIG=debug
APP_NAME="Ortus.app"
APPEARANCE=native
BUNDLE_ID=com.ortus.app
URL_SCHEME=ortus
IS_PREVIEW=false
IS_COMPARISON=false
case "$MODE" in
    release) CONFIG=release ;;
    preview) CONFIG=release; APP_NAME="Ortus Preview.app"; BUNDLE_ID=com.ortus.preview; URL_SCHEME=ortus-preview; IS_PREVIEW=true ;;
    native) CONFIG=release; APP_NAME="Ortus Native.app"; BUNDLE_ID=com.ortus.preview.native; URL_SCHEME=ortus-native; IS_PREVIEW=true; IS_COMPARISON=true ;;
    glass) CONFIG=release; APP_NAME="Ortus Glass.app"; BUNDLE_ID=com.ortus.preview.glass; URL_SCHEME=ortus-glass; IS_PREVIEW=true; IS_COMPARISON=true; APPEARANCE=glass ;;
    debug) ;;
    *) echo "Usage: ./build.sh [debug|release|preview|native|glass]" >&2; exit 1 ;;
esac

swift build -c "$CONFIG"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/$APP_NAME"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Ortus" "$APP/Contents/MacOS/Ortus"
cp ".build/$CONFIG/OrtusBrowserBridge" "$APP/Contents/MacOS/OrtusBrowserBridge"
chmod +x "$APP/Contents/MacOS/Ortus" "$APP/Contents/MacOS/OrtusBrowserBridge"
cp Ortus/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/BrowserExtension"
cp BrowserExtension/*.js BrowserExtension/*.html BrowserExtension/*.css BrowserExtension/manifest.json BrowserExtension/identity.json "$APP/Contents/Resources/BrowserExtension/"
# SwiftPM resource bundles may be consulted by the app or a dependency at runtime.
for RESOURCE in .build/"$CONFIG"/*.bundle; do
    [[ -d "$RESOURCE" ]] && cp -R "$RESOURCE" "$APP/Contents/Resources/"
done
if [[ "$IS_PREVIEW" == true ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_NAME%.app}" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.1.0-preview' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Add :OrtusPreviewBuild bool true' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :OrtusSourceCommit string $(git rev-parse --short HEAD)" "$APP/Contents/Info.plist"
    printf "export const NATIVE_HOST = 'com.ortus.browser.preview';\n" > "$APP/Contents/Resources/BrowserExtension/config.js"
fi
/usr/libexec/PlistBuddy -c "Add :OrtusAppearance string $APPEARANCE" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :OrtusComparisonBuild bool $IS_COMPARISON" "$APP/Contents/Info.plist"
if [[ "$IS_COMPARISON" == true ]]; then
    /usr/libexec/PlistBuddy -c 'Set :LSUIElement false' "$APP/Contents/Info.plist"
fi
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes array' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0 dict' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes array' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $URL_SCHEME" "$APP/Contents/Info.plist"
ICONSET="$STAGING/AppIcon.iconset"
mkdir -p "$ICONSET"
cp Ortus/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$APP/Contents/Info.plist"
codesign --force --sign "$SIGNING_IDENTITY" "$APP/Contents/MacOS/OrtusBrowserBridge"
codesign --force --sign "$SIGNING_IDENTITY" --entitlements Ortus/Ortus.entitlements "$APP"
codesign --verify --deep --strict "$APP"
# Building does not quit or replace a running installed app.
if [[ -d "$APP_NAME" ]]; then mv "$APP_NAME" "$STAGING/previous.app"; fi
mv "$APP" "$APP_NAME"
if [[ "$MODE" == release ]]; then
    ditto -c -k --keepParent "$APP_NAME" Ortus-macOS.zip
    echo "Packaged Ortus-macOS.zip"
fi
echo "Built $APP_NAME — run with: open \"$APP_NAME\""
