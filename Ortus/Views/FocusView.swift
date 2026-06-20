import SwiftUI

struct FocusView: View {
    @EnvironmentObject var focusManager: FocusManager
    @State private var manualDuration: Double = 60
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: OrtusTheme.spacingLG) {
            if focusManager.isInFocus && focusManager.isInGracePeriod {
                gracePeriodState
            } else if focusManager.isInFocus {
                activeFocusState
            } else {
                idleState
            }

            if !focusManager.isInFocus && !focusManager.isEmergencyEnded && !focusManager.schedules.isEmpty {
                let activeSchedules = focusManager.schedules.filter(\.isEnabled)
                if !activeSchedules.isEmpty {
                    scheduleBadge(count: activeSchedules.count)
                }
            }
        }
        .padding(OrtusTheme.spacingMD)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func scheduleBadge(count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .semibold))
            Text("\(count) schedule\(count == 1 ? "" : "s") active")
                .font(OrtusTheme.Typo.meta)
        }
        .foregroundStyle(OrtusTheme.textMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(OrtusTheme.cardSurface))
        .overlay(Capsule().strokeBorder(OrtusTheme.hairline, lineWidth: 1))
    }

    // MARK: - Grace Period

    private var gracePeriodState: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            if let graceEnd = focusManager.gracePeriodEndTime {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let remaining = max(0, graceEnd.timeIntervalSince(context.date))
                    ZStack {
                        Circle()
                            .stroke(OrtusTheme.accent.opacity(0.14), lineWidth: 5)
                            .frame(width: 124, height: 124)

                        Circle()
                            .trim(from: 0, to: remaining / 30)
                            .stroke(OrtusTheme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 124, height: 124)
                            .rotationEffect(.degrees(-90))

                        Text("\(Int(ceil(remaining)))")
                            .font(OrtusTheme.Typo.display)
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                }
            }

            VStack(spacing: OrtusTheme.spacingXS) {
                Text("Focus starting")
                    .font(OrtusTheme.Typo.title)
                Text("Forgot something? You can still go back.")
                    .font(OrtusTheme.Typo.body)
                    .foregroundStyle(OrtusTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OrtusTheme.spacingLG)
            }

            Button("Never mind") { focusManager.revertFocusSession() }
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
                    .tracking(2.2)
                    .foregroundStyle(OrtusTheme.accent)

                if let name = focusManager.currentSessionName {
                    Text(name)
                        .font(OrtusTheme.Typo.bodyMedium)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                focusManager.extendFocus(by: 15 * 60)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("15 min")
                }
            }
            .buttonStyle(OrtusSecondaryButtonStyle())
            .help("Add 15 minutes to this focus session")

            if focusManager.developerModeEnabled {
                Button("End focus (dev)") { focusManager.endFocusSession() }
                    .buttonStyle(OrtusGhostButtonStyle())
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    private func timerHero(remaining: TimeInterval, progress: Double) -> some View {
        ZStack {
            // Breathing dawn aura
            Circle()
                .fill(OrtusTheme.dawnGlow)
                .frame(width: 270, height: 270)
                .scaleEffect(isPulsing ? 1.06 : 0.92)
                .opacity(isPulsing ? 0.9 : 0.55)
                .blur(radius: 14)

            // Glass disc
            Circle()
                .fill(OrtusTheme.cardRaised)
                .frame(width: 196, height: 196)
                .overlay(Circle().strokeBorder(OrtusTheme.innerHighlight, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 22, y: 7)

            // Track
            Circle()
                .stroke(OrtusTheme.accent.opacity(0.12), lineWidth: 4)
                .frame(width: 196, height: 196)

            // Dawn-gradient progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: OrtusTheme.dawnColors + [OrtusTheme.dawnColors[0]], center: .center),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 196, height: 196)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)

            // Hero clock
            if remaining > 0 {
                Text(formatDuration(remaining))
                    .font(OrtusTheme.Typo.hero)
                    .tracking(-2)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
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

    // MARK: - Idle

    private var idleState: some View {
        VStack(spacing: OrtusTheme.spacingLG) {
            OrtusSunmark(showGlow: true)
                .frame(width: 132, height: 132)

            VStack(spacing: OrtusTheme.spacingXS) {
                Text("Ready when you are")
                    .font(OrtusTheme.Typo.title)
                Text("Begin a session and Slack goes dark until you're done.")
                    .font(OrtusTheme.Typo.body)
                    .foregroundStyle(OrtusTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OrtusTheme.spacingLG)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                focusManager.startFocusSession(name: "Manual Focus", duration: manualDuration * 60)
            }
            .buttonStyle(OrtusPrimaryButtonStyle())
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
