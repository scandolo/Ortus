#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --target OrtusCore
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
swiftc -parse-as-library -I .build/debug/Modules .build/debug/OrtusCore.build/*.swift.o \
    Ortus/Views/OrtusTheme.swift Ortus/Views/OrtusComponents.swift \
    scripts/ModalScrollingChecks.swift -o "$TEMP/checks"
"$TEMP/checks"
