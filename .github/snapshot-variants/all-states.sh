#!/bin/bash
# Every panel state the state board maps, at 2x, in light and dark. Swaps in an extended
# snapshot harness and opens the few hooks it needs, in this CI checkout only.
set -euo pipefail
V=.github/snapshot-variants/all-states
applied() { grep -q -- "$1" "$2" || { echo "Variant patch did not apply: '$1' in $2" >&2; exit 1; }; }

cp "$V/SnapshotHarness.swift" Ortus/Debug/SnapshotHarness.swift

# Let the harness put services into any state.
sed -i '' 's/@Published private(set) var/@Published var/' Ortus/Services/*.swift
applied '@Published var connectedBrowsers' Ortus/Services/WebsiteBlockingService.swift

# Hand the harness the services it sets, add an "existing mode" modal, and render the
# menu bar countdown at 2x.
perl -0pi -e 's/(\n(\s*)SnapshotHarness\.runIfRequested\(focusManager: focusManager\))/\n$2SnapshotHarness.claude = claudeCodeService\n$2SnapshotHarness.slack = slackOAuthService\n$2SnapshotHarness.updates = updateService$1/' Ortus/OrtusApp.swift
applied 'SnapshotHarness.updates = updateService' Ortus/OrtusApp.swift
perl -0pi -e 's/(\n(\s*)default: nil\n)/\n$2case "mode-editor-existing": focusManager.customModes.first.map { mode in PanelModal.modeEditor(mode) { _ in } }$1/' Ortus/OrtusApp.swift
applied 'mode-editor-existing' Ortus/OrtusApp.swift
perl -0pi -e 's/private static func countdownImage/static func countdownImage/; s/renderer\.scale = NSScreen\.main\?\.backingScaleFactor \?\? 2/renderer.scale = 2/' Ortus/OrtusApp.swift
applied 'renderer.scale = 2$' Ortus/OrtusApp.swift

# No live update check, so each update state is the one the harness sets.
perl -0pi -e 's/Task \{ await updateService\.checkForUpdates\(\) \}/if ProcessInfo.processInfo.environment["ORTUS_SNAPSHOT_DIR"] == nil { Task { await updateService.checkForUpdates() } }/' Ortus/Views/ContentView.swift
applied 'ORTUS_SNAPSHOT_DIR' Ortus/Views/ContentView.swift

# Open an existing schedule for editing.
perl -0pi -e 's/if snapshotState == "new-schedule" \{ isAddingNew = true \}/if snapshotState == "new-schedule" { isAddingNew = true } else if snapshotState == "edit-schedule" { editingScheduleID = focusManager.schedules.last?.id }/' Ortus/Views/ScheduleView.swift
applied 'edit-schedule' Ortus/Views/ScheduleView.swift

# Settings: the emergency confirmation and the Slack status preview.
perl -0pi -e 's/(\@AppStorage\(Analytics\.consentKey\) private var shareUsage = false)/$1\n    \@Environment(\\.snapshotState) private var snapshotState/' Ortus/Views/SettingsView.swift
perl -0pi -e 's/(\n(\s*)claudeCodeService\.detectIfNeeded\(\)\n)/$1$2if snapshotState == "emergency-confirm" { showEmergencyConfirm = true }\n$2if snapshotState == "slack-preview" { showSlackPreview = true }\n/' Ortus/Views/SettingsView.swift
applied 'private var snapshotState' Ortus/Views/SettingsView.swift
applied 'emergency-confirm' Ortus/Views/SettingsView.swift
