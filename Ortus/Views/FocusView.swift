import SwiftUI

struct FocusView: View {
    @EnvironmentObject var focusManager: FocusManager
    @State private var manualDuration: Double = 60

    var body: some View {
        VStack(spacing: OrtusTheme.spacingLG) {
            Spacer()

            if focusManager.isEmergencyEnded {
                emergencyEndedState
            } else if focusManager.isInFocus {
                activeFocusState
            } else {
                idleState
            }

            Spacer()

            if !focusManager.isInFocus && !focusManager.isEmergencyEnded && !focusManager.schedules.isEmpty {
                let activeSchedules = focusManager.schedules.filter(\.isEnabled)
                if !activeSchedules.isEmpty {
                    Text("\(activeSchedules.count) schedule\(activeSchedules.count == 1 ? "" : "s") active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(OrtusTheme.spacingMD)
    }

    // MARK: - Active Focus

    private var activeFocusState: some View {
        VStack(spacing: OrtusTheme.spacingLG) {
            ZStack {
                Circle()
                    .fill(OrtusTheme.primaryLight)
                    .frame(width: 120, height: 120)

                Image(systemName: "sunrise.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(OrtusTheme.primary)
            }

            Text("Focus Mode Active")
                .font(.title2.bold())

            if let name = focusManager.currentSessionName {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let endTime = focusManager.focusEndTime {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = endTime.timeIntervalSince(context.date)
                    if remaining > 0 {
                        Text(formatDuration(remaining))
                            .font(.system(.title3, design: .monospaced))
                            .foregroundStyle(OrtusTheme.primary)
                    } else {
                        Text("Ending...")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if focusManager.developerModeEnabled {
                Button("End Focus (Dev)") {
                    focusManager.endFocusSession()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Emergency Ended

    private var emergencyEndedState: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            ZStack {
                Circle()
                    .fill(OrtusTheme.warningLight)
                    .frame(width: 120, height: 120)

                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(OrtusTheme.warning)
            }

            Text("Slack Still Blocked")
                .font(.title2.bold())

            if let originalEnd = focusManager.originalFocusEndTime {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = originalEnd.timeIntervalSince(context.date)
                    if remaining > 0 {
                        Text("Unblocks in \(formatDuration(remaining))")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(OrtusTheme.warning)
                    } else {
                        Text("Unblocking...")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Focus was emergency-ended, but Slack remains blocked until the original end time.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OrtusTheme.spacingLG)
        }
    }

    // MARK: - Idle

    private var idleState: some View {
        VStack(spacing: OrtusTheme.spacingLG) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "sunrise")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }

            Text("Focus Mode Off")
                .font(.title2.bold())

            VStack(spacing: OrtusTheme.spacingMD) {
                HStack {
                    Text("Duration")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(manualDuration)) min")
                        .monospacedDigit()
                }

                Slider(value: $manualDuration, in: 15...240, step: 15)
                    .tint(OrtusTheme.primary)
            }
            .padding(.horizontal, 30)

            Button("Start Focus") {
                focusManager.startFocusSession(
                    name: "Manual Focus",
                    duration: manualDuration * 60
                )
            }
            .buttonStyle(OrtusPrimaryButtonStyle())
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
