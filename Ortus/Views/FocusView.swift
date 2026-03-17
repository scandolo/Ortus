import SwiftUI

struct FocusView: View {
    @EnvironmentObject var focusManager: FocusManager
    @State private var manualDuration: Double = 60
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: OrtusTheme.spacingLG) {
            Spacer()

            if focusManager.isEmergencyEnded {
                emergencyEndedState
            } else if focusManager.isInFocus && focusManager.isInGracePeriod {
                gracePeriodState
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
                        .font(.system(size: 12))
                        .foregroundStyle(OrtusTheme.textSecondary)
                }
            }
        }
        .padding(OrtusTheme.spacingMD)
    }

    // MARK: - Grace Period

    private var gracePeriodState: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            if let graceEnd = focusManager.gracePeriodEndTime {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let remaining = max(0, graceEnd.timeIntervalSince(context.date))
                    ZStack {
                        // Progress ring
                        Circle()
                            .stroke(OrtusTheme.accent.opacity(0.15), lineWidth: 4)
                            .frame(width: 120, height: 120)

                        Circle()
                            .trim(from: 0, to: remaining / 30)
                            .stroke(OrtusTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))

                        Text("\(Int(ceil(remaining)))")
                            .font(.system(size: 48, weight: .light, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }
            }

            Text("Focus starting...")
                .font(.system(size: 18, weight: .semibold))

            Text("Forgot something? You can still go back.")
                .font(.system(size: 12))
                .foregroundStyle(OrtusTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OrtusTheme.spacingLG)

            Button("Never mind") {
                focusManager.revertFocusSession()
            }
            .buttonStyle(OrtusSecondaryButtonStyle())
        }
    }

    // MARK: - Active Focus

    private var activeFocusState: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            if let endTime = focusManager.focusEndTime {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = endTime.timeIntervalSince(context.date)
                    ZStack {
                        // Breathing pulse circle
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        OrtusTheme.accentSoft.opacity(isPulsing ? 0.15 : 0.0),
                                        OrtusTheme.accentSoft.opacity(0.0)
                                    ]),
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 100
                                )
                            )
                            .frame(width: 200, height: 200)

                        // Hero timer
                        if remaining > 0 {
                            Text(formatDuration(remaining))
                                .font(.system(size: 56, weight: .light, design: .rounded))
                                .tracking(-2)
                                .foregroundStyle(.primary)
                        } else {
                            Text("Ending")
                                .font(.system(size: 56, weight: .light, design: .rounded))
                                .tracking(-2)
                                .foregroundStyle(OrtusTheme.textSecondary)
                        }
                    }
                }
            }

            // Quiet label
            Text("deep focus")
                .font(.system(size: 12))
                .foregroundStyle(OrtusTheme.textSecondary)

            if let name = focusManager.currentSessionName {
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(OrtusTheme.textSecondary)
            }

            if focusManager.developerModeEnabled {
                Button("End focus (dev)") {
                    focusManager.endFocusSession()
                }
                .font(.system(size: 12))
                .foregroundStyle(OrtusTheme.textSecondary)
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    // MARK: - Emergency Ended

    private var emergencyEndedState: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            ZStack {
                Circle()
                    .fill(OrtusTheme.warning.opacity(0.10))
                    .frame(width: 120, height: 120)

                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(OrtusTheme.warning)
            }

            Text("Slack still paused")
                .font(.system(size: 18, weight: .semibold))

            if let originalEnd = focusManager.originalFocusEndTime {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = originalEnd.timeIntervalSince(context.date)
                    if remaining > 0 {
                        Text("Unblocks in \(formatDuration(remaining))")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(OrtusTheme.warning)
                    } else {
                        Text("Unblocking")
                            .font(.system(size: 13))
                            .foregroundStyle(OrtusTheme.textSecondary)
                    }
                }
            }

            Text("Focus ended early. Slack stays paused until the original time.")
                .font(.system(size: 12))
                .foregroundStyle(OrtusTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OrtusTheme.spacingLG)
        }
    }

    // MARK: - Idle

    private var idleState: some View {
        VStack(spacing: OrtusTheme.spacingLG) {
            Image(systemName: "sunrise")
                .font(.system(size: 56))
                .foregroundStyle(OrtusTheme.textTertiary)

            Text("Ready when you are")
                .font(.system(size: 18, weight: .semibold))

            VStack(spacing: OrtusTheme.spacingMD) {
                HStack {
                    Text("Duration")
                        .font(.system(size: 13))
                        .foregroundStyle(OrtusTheme.textSecondary)
                    Spacer()
                    Text("\(Int(manualDuration)) min")
                        .monospacedDigit()
                }

                Slider(value: $manualDuration, in: 15...240, step: 15)
                    .tint(OrtusTheme.accent)
            }
            .padding(.horizontal, 30)

            Button("Begin focus") {
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
