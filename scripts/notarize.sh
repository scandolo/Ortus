#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Notarizes a Developer ID signed release and packages the two downloads:
#   Ortus-macOS.zip  the stapled app, used by the in-app updater and install.sh
#   Ortus.dmg        the drag-to-Applications download for the website
#
# Run after `ORTUS_SIGNING_IDENTITY=<identity> ./build.sh release`. Needs an App Store
# Connect API key: NOTARY_KEY_PATH (.p8 file), NOTARY_KEY_ID, NOTARY_ISSUER_ID.

: "${ORTUS_SIGNING_IDENTITY:?Set the Developer ID Application identity}"
: "${NOTARY_KEY_PATH:?Set the path to the App Store Connect API key (.p8)}"
: "${NOTARY_KEY_ID:?Set the API key ID}"
: "${NOTARY_ISSUER_ID:?Set the API key issuer ID}"
APP=Ortus.app
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Submits a file to Apple, waits, and prints Apple's log if it isn't accepted.
notarize() {
    local key=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
    local result id status
    result=$(xcrun notarytool submit "$1" "${key[@]}" --wait --output-format json)
    id=$(plutil -extract id raw -o - - <<< "$result")
    status=$(plutil -extract status raw -o - - <<< "$result")
    if [[ "$status" != Accepted ]]; then
        xcrun notarytool log "$id" "${key[@]}" >&2 || true
        echo "✗ Notarization of $1: $status" >&2
        exit 1
    fi
    echo "Notarized $1"
}

# 1. The app. Stapling attaches the ticket so the first launch works offline too.
ditto -c -k --keepParent "$APP" "$WORK/Ortus.zip"
notarize "$WORK/Ortus.zip"
xcrun stapler staple "$APP"
rm -f Ortus-macOS.zip
ditto -c -k --keepParent "$APP" Ortus-macOS.zip

# 2. The dmg around the stapled app, with an Applications shortcut to drag onto.
mkdir "$WORK/dmg"
ditto "$APP" "$WORK/dmg/$APP"
ln -s /Applications "$WORK/dmg/Applications"
rm -f Ortus.dmg
# hdiutil sometimes fails with "Resource busy" on CI runners; a retry clears it.
for attempt in 1 2 3; do
    hdiutil create -volname Ortus -srcfolder "$WORK/dmg" -fs HFS+ -format UDZO Ortus.dmg && break
    [[ $attempt == 3 ]] && exit 1
    sleep 5
done
codesign --force --sign "$ORTUS_SIGNING_IDENTITY" --timestamp Ortus.dmg
notarize Ortus.dmg
xcrun stapler staple Ortus.dmg

# 3. Check them the way Gatekeeper will on a user's Mac.
spctl --assess --type exec -vv "$APP"
spctl --assess --type open --context context:primary-signature -vv Ortus.dmg
echo "Packaged Ortus-macOS.zip and Ortus.dmg"
