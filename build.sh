#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Local builds use ad-hoc signing: no keychain import, password, or trust dialog.
# Website blocking uses a Native Messaging companion, not signature-bound TCC.
# CI passes a Developer ID identity for releases (see .github/workflows/release.yml).
SIGNING_IDENTITY="${ORTUS_SIGNING_IDENTITY:--}"
MODE="${1:-debug}"
CONFIG=debug
APP_NAME="Ortus.app"
BUNDLE_ID=com.ortusmode.app
URL_SCHEME=ortus
IS_PREVIEW=false
case "$MODE" in
    release) CONFIG=release ;;
    preview) CONFIG=release; IS_PREVIEW=true ;;
    # Debug builds are previews too. With the release identity they shared settings,
    # login item, session lock and browser rules with the installed app.
    debug) IS_PREVIEW=true ;;
    *) echo "Usage: ./build.sh [debug|release|preview]" >&2; exit 1 ;;
esac
if [[ "$IS_PREVIEW" == true ]]; then APP_NAME="Ortus Preview.app"; BUNDLE_ID=com.ortusmode.preview; URL_SCHEME=ortus-preview; fi

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
if [[ "$MODE" == release ]]; then
    # Releases run on Apple silicon and Intel: build each architecture, then merge.
    for ARCH in arm64 x86_64; do swift build -c release --triple "$ARCH-apple-macosx14.0"; done
    BIN_DIR=".build/arm64-apple-macosx/release"
    for EXECUTABLE in Ortus OrtusBrowserBridge; do
        lipo -create -output "$STAGING/$EXECUTABLE" ".build/arm64-apple-macosx/release/$EXECUTABLE" ".build/x86_64-apple-macosx/release/$EXECUTABLE"
    done
else
    swift build -c "$CONFIG"
    BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)
    cp "$BIN_DIR/Ortus" "$BIN_DIR/OrtusBrowserBridge" "$STAGING/"
fi
APP="$STAGING/$APP_NAME"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$STAGING/Ortus" "$APP/Contents/MacOS/Ortus"
mv "$STAGING/OrtusBrowserBridge" "$APP/Contents/MacOS/OrtusBrowserBridge"
chmod +x "$APP/Contents/MacOS/Ortus" "$APP/Contents/MacOS/OrtusBrowserBridge"
cp Ortus/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/BrowserExtension"
cp BrowserExtension/*.js BrowserExtension/*.html BrowserExtension/*.css BrowserExtension/*.png BrowserExtension/manifest.json BrowserExtension/identity.json "$APP/Contents/Resources/BrowserExtension/"
# SwiftPM resource bundles may be consulted by the app or a dependency at runtime.
for RESOURCE in "$BIN_DIR"/*.bundle; do
    [[ -d "$RESOURCE" ]] && cp -R "$RESOURCE" "$APP/Contents/Resources/"
done
if [[ "$IS_PREVIEW" == true ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_NAME%.app}" "$APP/Contents/Info.plist"
    # Settings shows this, so a preview says which commit it was built from and when.
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString preview $(git rev-parse --short HEAD) · $(date '+%b %-d %H:%M')" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Add :OrtusPreviewBuild bool true' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :OrtusSourceCommit string $(git rev-parse --short HEAD)" "$APP/Contents/Info.plist"
    printf "export const NATIVE_HOST = 'com.ortus.browser.preview';\n" > "$APP/Contents/Resources/BrowserExtension/config.js"
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
SIGN=(codesign --force --sign "$SIGNING_IDENTITY")
# Notarization requires the hardened runtime and a secure timestamp. Ad-hoc builds can't
# be timestamped, and local builds don't need either.
if [[ "$SIGNING_IDENTITY" != "-" ]]; then SIGN+=(--options runtime --timestamp); fi
"${SIGN[@]}" "$APP/Contents/MacOS/OrtusBrowserBridge"
"${SIGN[@]}" --entitlements Ortus/Ortus.entitlements "$APP"
codesign --verify --deep --strict "$APP"
# Building does not quit or replace a running installed app.
if [[ -d "$APP_NAME" ]]; then mv "$APP_NAME" "$STAGING/previous.app"; fi
mv "$APP" "$APP_NAME"
if [[ "$MODE" == release ]]; then
    ditto -c -k --keepParent "$APP_NAME" Ortus-macOS.zip
    echo "Packaged Ortus-macOS.zip"
fi
echo "Built $APP_NAME — run with: open \"$APP_NAME\""
