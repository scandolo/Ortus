#!/bin/bash
set -euo pipefail

# Usage: scripts/make-dmg.sh <Some.app> <out.dmg>
#
# Packs the app into a drag-to-Applications disk image. Needs no signing, so it runs
# on any Mac. With dmgbuild (pip install dmgbuild==1.6.5) the window is the designed
# one from scripts/dmg/. Without it, or if dmgbuild fails for any reason, the image is
# the plain one (the app next to an Applications shortcut) so a release never breaks.
# Set ORTUS_DMG_PLAIN=1 to force the plain one. Signing and notarizing are the caller's.

APP=${1:?Usage: make-dmg.sh <Some.app> <out.dmg>}
OUT=${2:?Usage: make-dmg.sh <Some.app> <out.dmg>}
[[ -d "$APP" ]] || { echo "No such app: $APP" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

plain() {
    mkdir "$WORK/plain"
    ditto "$APP" "$WORK/plain/$(basename "$APP")"
    ln -s /Applications "$WORK/plain/Applications"
    rm -f "$OUT"
    # hdiutil sometimes fails with "Resource busy" on CI runners; a retry clears it.
    for attempt in 1 2 3; do
        hdiutil create -volname Ortus -srcfolder "$WORK/plain" -fs HFS+ -format UDZO "$OUT" && return
        [[ $attempt == 3 ]] && return 1
        sleep 5
    done
}

styled() {
    local dmgbuild=${DMGBUILD:-dmgbuild}
    command -v "$dmgbuild" >/dev/null || { echo "dmgbuild not installed" >&2; return 1; }
    rm -f "$OUT"
    "$dmgbuild" -s "$HERE/dmg/settings.py" -D app="$APP" -D here="$HERE/dmg" Ortus "$OUT" && [[ -s "$OUT" ]]
}

if [[ "${ORTUS_DMG_PLAIN:-}" != 1 ]] && styled; then
    echo "Made the designed $OUT"
else
    [[ "${ORTUS_DMG_PLAIN:-}" == 1 ]] || echo "::warning::The designed dmg failed, so this one is the plain one." >&2
    rm -f "$OUT"
    plain
    echo "Made the plain $OUT"
fi
