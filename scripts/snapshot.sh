#!/bin/bash
# Render every panel state to PNGs: scripts/snapshot.sh <out-dir> [--session]
# Uses a throwaway copy of the debug build with its own settings, so it never touches
# the installed app. --session also renders the grace countdown, a running session and
# Settings during focus: it starts a real session that blocks the Socials websites in
# the preview browser companion for about a minute. Socials closes no apps.
set -euo pipefail
[[ $# -ge 1 ]] || { echo "Usage: scripts/snapshot.sh <out-dir> [--session]" >&2; exit 1; }
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
SESSION=${2:-}
cd "$(dirname "$0")/.." && cd "$(pwd -P)"
APP="$PWD/Ortus Preview.app"
ID=com.ortusmode.snapshot
pkill -9 -f "^$APP/Contents/MacOS/Ortus$" 2>/dev/null || true
./build.sh debug >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ID" "$APP/Contents/Info.plist"
codesign --force --sign - --entitlements Ortus/Ortus.entitlements "$APP" 2>/dev/null
defaults delete $ID 2>/dev/null || true
rm -f "$OUT"/*.png
# Every launch points the preview's browser connection at the running build. Put the
# installed preview's files back afterwards.
HOSTS=$(mktemp -d)
for d in "Google/Chrome" "Arc/User Data" "Microsoft Edge" "BraveSoftware/Brave-Browser" "Chromium"; do
    f="$HOME/Library/Application Support/$d/NativeMessagingHosts/com.ortus.browser.preview.json"
    [[ -f "$f" ]] && mkdir -p "$HOSTS/$d" && cp "$f" "$HOSTS/$d/"
done
# Leave nothing behind: the browser files go back and the throwaway settings go away.
clean_up() {
    (cd "$HOSTS" && find . -name '*.json' | while read -r f; do cp "$f" "$HOME/Library/Application Support/$(dirname "${f#./}")/NativeMessagingHosts/"; done); rm -rf "$HOSTS"
    pkill -9 -f "^$APP/Contents/MacOS/Ortus$" 2>/dev/null || true
    defaults delete $ID 2>/dev/null || true
}
trap clean_up EXIT
open --env "ORTUS_SNAPSHOT_DIR=$OUT" ${SESSION:+--env ORTUS_SNAPSHOT_SESSION=1} "$APP"
running() { pgrep -f "^$APP/Contents/MacOS/Ortus$" >/dev/null; }
for _ in $(seq 1 30); do running && break; sleep 1; done
for _ in $(seq 1 180); do running || break; sleep 1; done
ls "$OUT"
