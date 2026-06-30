#!/bin/bash
set -euo pipefail

# Ortus installer.
#
# Downloads the latest release, installs to /Applications, and launches it.
# Because this runs via `curl | bash` (not a browser download), macOS does not
# attach the com.apple.quarantine flag, so Gatekeeper does not block the app.

REPO="scandolo/Ortus"
APP_NAME="Ortus.app"
ZIP_URL="https://github.com/${REPO}/releases/latest/download/Ortus-macOS.zip"
DEST="/Applications"

echo "→ Downloading Ortus…"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! curl -fsSL "$ZIP_URL" -o "$TMP/Ortus-macOS.zip"; then
    echo "✗ Download failed. Is there a published release at https://github.com/${REPO}/releases ?" >&2
    exit 1
fi

echo "→ Installing to ${DEST}/${APP_NAME}…"
# Quit any running instance so we can overwrite it cleanly.
osascript -e 'quit app "Ortus"' >/dev/null 2>&1 || true
pkill -f "Ortus.app/Contents/MacOS/Ortus" >/dev/null 2>&1 || true
sleep 1

mkdir -p "$TMP/unzipped"
ditto -x -k "$TMP/Ortus-macOS.zip" "$TMP/unzipped"

SRC_APP="$TMP/unzipped/${APP_NAME}"
if [ ! -d "$SRC_APP" ]; then
    SRC_APP="$(find "$TMP/unzipped" -maxdepth 2 -name "${APP_NAME}" -type d | head -1)"
fi
if [ -z "${SRC_APP:-}" ] || [ ! -d "$SRC_APP" ]; then
    echo "✗ Could not find ${APP_NAME} inside the download." >&2
    exit 1
fi

if [ ! -w "$DEST" ]; then
    echo "✗ No write access to ${DEST}. Re-run with: curl -fsSL <url> | sudo bash" >&2
    exit 1
fi

rm -rf "${DEST:?}/${APP_NAME}"
mv "$SRC_APP" "${DEST}/"

# Strip the quarantine flag just in case (harmless if not present).
xattr -dr com.apple.quarantine "${DEST}/${APP_NAME}" >/dev/null 2>&1 || true

echo "→ Launching Ortus…"
open "${DEST}/${APP_NAME}"

echo "✓ Ortus installed. Look for the sun in your menu bar."
