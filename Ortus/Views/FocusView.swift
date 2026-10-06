import SwiftUI
import OrtusCore

struct FocusView: View {
    @EnvironmentObject var focusManager: FocusManager
    @State private var manualDuration: Double = 60

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(spacing: OrtusTheme.spacingLG) {
                if !(focusManager.isInFocus ? focusManager.activeSelection : focusManager.manualSelection).websites.isEmpty,
                   focusManager.websites.connectedBrowsers.isEmpty {
                    OrtusGroup { BrowserStatusRow(service: focusManager.websites) }
                }
                if focusManager.isInFocus && focusManager.isInGracePeriod {
                    gracePeriodState
                } else if focusManager.isInFocus {
                    activeFocusState
                } else {
                    idleState
                }
            }
            .padding(OrtusTheme.spacingMD)
        }
            // The primary action stays pinned and visible, like "Add schedule".
            if !focusManager.isInFocus {
                Button {
                    focusManager.startFocusSession(name: "Focus", duration: manualDuration * 60)
                } label: {
                    Text("Begin \(Int(manualDuration)) min focus").frame(maxWidth: .infinity)
                }
                .buttonStyle(OrtusPrimaryButtonStyle())
                .disabled(focusManager.manualSelection.isEmpty)
                .padding(.horizontal, OrtusTheme.spacingMD)
                .padding(.bottom, OrtusTheme.spacingSM)
            }
        }
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
                Text(focusManager.currentSessionName ?? "Focus")
                    .font(OrtusTheme.Typo.headline)
                Text(focusManager.activeSelection.summary)
                    .font(OrtusTheme.Typo.body).foregroundStyle(OrtusTheme.textMuted)
                    .multilineTextAlignment(.center)
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
    }

    private func timerHero(remaining: TimeInterval, progress: Double) -> some View {
        ZStack {
            // Static glow: never start a repeating layout transaction as the menu panel opens.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            OrtusTheme.accentSoft.opacity(0.32),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 110
                    )
                )
                .frame(width: 220, height: 220)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 164)
            } else {
                Text("Ending")
                    .font(OrtusTheme.Typo.hero)
                    .tracking(-2)
                    .foregroundStyle(OrtusTheme.textMuted)
            }
        }
        .frame(width: 220, height: 220)
    }

    private func totalSessionDuration(endingAt end: Date) -> TimeInterval {
        if let start = focusManager.focusStartTime {
            return max(end.timeIntervalSince(start), 1)
        }
        return max(end.timeIntervalSinceNow * 2, 60 * 15)
    }

    // MARK: - Idle

    private var idleState: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [OrtusTheme.accentSoft.opacity(0.7), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 36
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: "sunrise.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(OrtusTheme.accent)
                    .symbolRenderingMode(.hierarchical)
            }

            Text("Ready when you are")
                .font(OrtusTheme.Typo.title)

            VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                OrtusDurationSlider(
                    minutes: $manualDuration,
                    range: 15...240,
                    ticks: [15, 30, 60, 90, 120, 180, 240],
                    step: 15
                )
            }
            .ortusCard()

            ModePicker(selection: $focusManager.manualSelection)

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
