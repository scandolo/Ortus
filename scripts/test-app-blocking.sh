#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product Ortus
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
FIXTURE="$TEMP/Ortus Test Fixture.app"
mkdir -p "$FIXTURE/Contents/MacOS"
cat > "$TEMP/Fixture.swift" <<'SWIFT'
import AppKit
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateCancel }
}
let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
SWIFT
cat > "$FIXTURE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.ortus-test.disposable</string>
<key>CFBundleExecutable</key><string>Fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc "$TEMP/Fixture.swift" -o "$FIXTURE/Contents/MacOS/Fixture"
codesign --force --sign - "$FIXTURE"
swiftc -parse-as-library -I .build/debug/Modules .build/debug/OrtusCore.build/*.swift.o \
    Ortus/Services/ApplicationBlocker.swift scripts/AppBlockingChecks.swift -o "$TEMP/checks"
"$TEMP/checks" "$FIXTURE"
