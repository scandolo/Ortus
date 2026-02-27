#!/bin/bash
set -e
cd "$(dirname "$0")"

# Kill any running Ortus instances
pkill -f Ortus 2>/dev/null || true

swift build

APP_DIR="Ortus.app/Contents/MacOS"
rm -rf Ortus.app
mkdir -p "$APP_DIR"
cp .build/debug/Ortus "$APP_DIR/Ortus"
cp Ortus/Info.plist Ortus.app/Contents/Info.plist

# Prevent bare binary execution (avoids duplicate System Settings entries)
chmod -x .build/debug/Ortus 2>/dev/null || true

echo "Built Ortus.app — run with: open Ortus.app"
echo ""
echo "NOTE: If you see duplicate entries in System Settings > Login Items,"
echo "remove any 'Ortus' entry that isn't the .app bundle."
