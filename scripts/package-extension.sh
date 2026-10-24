#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Packages BrowserExtension/ for the Chrome Web Store as Ortus-extension.zip.
# The store assigns its own extension ID, so the upload leaves out the manifest's
# `key` (which pins the ID for local "Load unpacked" builds), the tests, and
# identity.json (read only by the Mac app).

OUT="$PWD/Ortus-extension.zip"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp BrowserExtension/*.js BrowserExtension/*.html BrowserExtension/*.css BrowserExtension/*.png "$STAGE/"
python3 - BrowserExtension/manifest.json "$STAGE/manifest.json" <<'EOF'
import json, sys
manifest = json.load(open(sys.argv[1]))
manifest.pop("key", None)
json.dump(manifest, open(sys.argv[2], "w"), indent=2, ensure_ascii=False)
EOF

rm -f "$OUT"
(cd "$STAGE" && zip -q -X -r "$OUT" .)
echo "Packaged $(basename "$OUT") (version $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' BrowserExtension/manifest.json)):"
unzip -Z1 "$OUT" | sort | sed 's/^/  /'
