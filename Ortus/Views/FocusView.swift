import SwiftUI

struct FocusView: View {
    @EnvironmentObject var focusManager: FocusManager
    @State private var manualDuration: Double = 60
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: OrtusTheme.spacingLG) {
            if focusManager.isEmergencyEnded {
                emergencyEndedState
            } else if focusManager.isInFocus && focusManager.isInGracePeriod {
                gracePeriodState
            } else if focusManager.isInFocus {
                activeFocusState
            } else {
                idleState
            }

            if !focusManager.isInFocus && !focusManager.isEmergencyEnded && !focusManager.schedules.isEmpty {
                let activeSchedules = focusManager.schedules.filter(\.isEnabled)
                if !activeSchedules.isEmpty {
                    Text("\(activeSchedules.count) schedule\(activeSchedules.count == 1 ? "" : "s") active")
                        .font(OrtusTheme.Typo.meta)
                        .foregroundStyle(OrtusTheme.textMuted)
                }
            }
        }
        .padding(OrtusTheme.spacingMD)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Grace Period

    private var gracePeriodState: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            if let graceEnd = focusManager.gracePeriodEndTime {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let remaining = max(0, graceEnd.timeIntervalSince(context.date))
                    ZStack {
                        Circle()
                            .stroke(OrtusTheme.accent.opacity(0.15), lineWidth: 4)
                            .frame(width: 120, height: 120)

                        Circle()
                            .trim(from: 0, to: remaining / 30)
                            .stroke(OrtusTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))

                        Text("\(Int(ceil(remaining)))")
                            .font(OrtusTheme.Typo.display)
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                }
            }

            Text("Focus starting")
                .font(OrtusTheme.Typo.title)

            Text("Forgot something? You can still go back.")
                .font(OrtusTheme.Typo.body)
                .foregroundStyle(OrtusTheme.textMuted)
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
        VStack(spacing: OrtusTheme.spacingLG) {
            if let endTime = focusManager.focusEndTime {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, endTime.timeIntervalSince(context.date))
                    let totalDuration = totalSessionDuration(endingAt: endTime)
                    let progress = totalDuration > 0 ? remaining / totalDuration : 0
                    timerHero(remaining: remaining, progress: progress)
                }
            }

            VStack(spacing: OrtusTheme.spacingXS) {
                Text("DEEP FOCUS")
                    .font(OrtusTheme.Typo.section)
                    .tracking(1.4)
                    .foregroundStyle(OrtusTheme.textMuted)

                if let name = focusManager.currentSessionName {
                    Text(name)
                        .font(OrtusTheme.Typo.bodyMedium)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                focusManager.extendFocus(by: 15 * 60)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("15 min")
                }
            }
            .buttonStyle(OrtusSecondaryButtonStyle())
            .help("Add 15 minutes to this focus session")

            if focusManager.developerModeEnabled {
                Button("End focus (dev)") {
                    focusManager.endFocusSession()
                }
                .buttonStyle(OrtusGhostButtonStyle())
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    private func timerHero(remaining: TimeInterval, progress: Double) -> some View {
        ZStack {
            // Outer breathing aura
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            OrtusTheme.accentSoft.opacity(isPulsing ? 0.55 : 0.20),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 130
                    )
                )
                .frame(width: 260, height: 260)
                .blur(radius: 10)

            // Glass disc — strong contrast against canvas
            Circle()
                .fill(OrtusTheme.cardSurface)
                .frame(width: 190, height: 190)
                .overlay(
                    Circle().strokeBorder(OrtusTheme.innerHighlight, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.16), radius: 20, y: 6)

            // Track + progress ring
            Circle()
                .stroke(OrtusTheme.accent.opacity(0.12), lineWidth: 3)
                .frame(width: 190, height: 190)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [OrtusTheme.accent, OrtusTheme.accentHover, OrtusTheme.accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 190, height: 190)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)

            // Hero timer
            if remaining > 0 {
                Text(formatDuration(remaining))
                    .font(OrtusTheme.Typo.hero)
                    .tracking(-2)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            } else {
                Text("Ending")
                    .font(OrtusTheme.Typo.hero)
                    .tracking(-2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func totalSessionDuration(endingAt end: Date) -> TimeInterval {
        if let start = focusManager.focusStartTime {
            return max(end.timeIntervalSince(start), 1)
        }
        return max(end.timeIntervalSinceNow * 2, 60 * 15)
    }

    // MARK: - Emergency Ended

    private var emergencyEndedState: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            ZStack {
                Circle()
                    .fill(OrtusTheme.warning.opacity(0.14))
                    .frame(width: 120, height: 120)

                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(OrtusTheme.warning)
                    .symbolRenderingMode(.hierarchical)
            }

            Text("Slack still paused")
                .font(OrtusTheme.Typo.title)

            if let originalEnd = focusManager.originalFocusEndTime {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = originalEnd.timeIntervalSince(context.date)
                    if remaining > 0 {
                        Text("Unblocks in \(formatDuration(remaining))")
                            .font(OrtusTheme.Typo.bodyMedium)
                            .monospacedDigit()
                            .foregroundStyle(OrtusTheme.warning)
                    } else {
                        Text("Unblocking")
                            .font(OrtusTheme.Typo.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Focus ended early. Slack stays paused until the original time.")
                .font(OrtusTheme.Typo.body)
                .foregroundStyle(OrtusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OrtusTheme.spacingLG)
        }
    }

    // MARK: - Idle

    private var idleState: some View {
        VStack(spacing: OrtusTheme.spacingLG) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [OrtusTheme.accentSoft.opacity(0.7), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)

                Image(systemName: "sunrise.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(OrtusTheme.accent)
                    .symbolRenderingMode(.hierarchical)
            }

            Text("Ready when you are")
                .font(OrtusTheme.Typo.title)

            VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                OrtusSectionHeader(title: "Duration")

                OrtusDurationSlider(
                    minutes: $manualDuration,
                    range: 15...240,
                    ticks: [15, 30, 60, 90, 120, 180, 240],
                    step: 15
                )
            }
            .ortusCard()
            .padding(.horizontal, OrtusTheme.spacingLG)

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
