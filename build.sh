#!/bin/bash
set -e
cd "$(dirname "$0")"

SIGNING_IDENTITY="Ortus Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Usage: ./build.sh [release]
#   (no arg) → debug build for local dev
#   release  → optimized build + Ortus-macOS.zip for distribution (what install.sh downloads)
MODE="${1:-debug}"
if [ "$MODE" = "release" ]; then
    CONFIG="release"
else
    CONFIG="debug"
fi

# One-time bootstrap: create a local self-signed code-signing identity.
#
# Why: `swift build` produces a binary with no stable signature, so macOS treats
# every rebuild as a new app and re-asks the keychain prompt on every launch.
# Signing each build with the same self-signed cert gives Ortus a stable
# identity, so "Always Allow" on the keychain prompt actually persists.
if ! security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$SIGNING_IDENTITY"; then
    echo "→ One-time setup: creating local '$SIGNING_IDENTITY' code-signing identity"
    echo "  (macOS will prompt once for your login password to trust the cert)"
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    /usr/bin/openssl req -x509 -newkey rsa:2048 \
        -keyout "$TMP_DIR/key.pem" -out "$TMP_DIR/cert.pem" \
        -days 3650 -nodes \
        -subj "/CN=$SIGNING_IDENTITY" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" \
        -addext "basicConstraints=critical,CA:FALSE" \
        >/dev/null 2>&1

    # PEM import (not PKCS12) — security's PKCS12 importer is buggy on recent macOS.
    # -T /usr/bin/codesign adds a private-key ACL so codesign can use the key silently.
    security import "$TMP_DIR/cert.pem" -k "$KEYCHAIN" -T /usr/bin/codesign >/dev/null
    security import "$TMP_DIR/key.pem"  -k "$KEYCHAIN" -T /usr/bin/codesign >/dev/null
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP_DIR/cert.pem"

    echo "  ✓ '$SIGNING_IDENTITY' installed in login keychain"
fi

# Kill any running Ortus instances. Match the app binary path specifically — a
# bare `pkill -f Ortus` also matches anything with "Ortus" in its command line
# (the build's own compiler subprocesses, editors, agents in an Ortus/ checkout).
pkill -f 'Ortus.app/Contents/MacOS/Ortus' 2>/dev/null || true

if [ "$CONFIG" = "release" ]; then
    swift build -c release
else
    swift build
fi

APP_DIR="Ortus.app/Contents/MacOS"
RES_DIR="Ortus.app/Contents/Resources"
rm -rf Ortus.app
mkdir -p "$APP_DIR" "$RES_DIR"
cp ".build/$CONFIG/Ortus" "$APP_DIR/Ortus"
chmod +x "$APP_DIR/Ortus"   # source may have been chmod -x'd by a prior run
cp Ortus/Info.plist Ortus.app/Contents/Info.plist

# Bundle the Finder app icon (AppIcon.icns) from the asset catalog PNGs, if present.
ICONSET_SRC="Ortus/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICONSET_SRC" ] && command -v iconutil >/dev/null 2>&1; then
    TMP_ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$TMP_ICONSET"
    cp "$ICONSET_SRC"/icon_*.png "$TMP_ICONSET"/ 2>/dev/null || true
    iconutil -c icns "$TMP_ICONSET" -o "$RES_DIR/AppIcon.icns" 2>/dev/null \
        && echo "→ Bundled AppIcon.icns" \
        || echo "⚠︎ iconutil failed; app will use a generic icon"
    rm -rf "$(dirname "$TMP_ICONSET")"
fi

# Sign with the stable cert so keychain ACLs persist across rebuilds.
codesign --force --sign "$SIGNING_IDENTITY" \
    --entitlements Ortus/Ortus.entitlements \
    Ortus.app >/dev/null

# Prevent bare binary execution (avoids duplicate System Settings entries)
chmod -x ".build/$CONFIG/Ortus" 2>/dev/null || true

# Package a distributable zip for release builds (this is what install.sh downloads).
if [ "$CONFIG" = "release" ]; then
    rm -f Ortus-macOS.zip
    ditto -c -k --keepParent Ortus.app Ortus-macOS.zip
    echo "→ Packaged Ortus-macOS.zip ($(du -h Ortus-macOS.zip | cut -f1))"
fi

echo "Built Ortus.app — run with: open Ortus.app"
echo ""
echo "NOTE: If you see duplicate entries in System Settings > Login Items,"
echo "remove any 'Ortus' entry that isn't the .app bundle."
echo ""
echo "Credentials are stored in ~/Library/Application Support/Ortus/credentials.json"
echo "(chmod 0600), so there are no macOS keychain prompts on launch."
