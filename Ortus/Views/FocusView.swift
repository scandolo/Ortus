import SwiftUI
import OrtusCore

struct FocusView: View {
    @EnvironmentObject var focusManager: FocusManager
    @AppStorage("genZMode") private var genZ = false
    @State private var manualDuration: Double = 90

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
                    Text(startLabel).frame(maxWidth: .infinity)
                }
                .buttonStyle(OrtusPrimaryButtonStyle())
                .disabled(focusManager.manualSelection.isEmpty)
                .padding(.horizontal, OrtusTheme.spacingMD)
                .padding(.bottom, OrtusTheme.spacingSM)
            }
        }
    }

    /// The start button gets bolder as the session gets longer.
    private var startLabel: String {
        switch manualDuration {
        case 180...: genZ ? "start winter arc" : "Enter monk mode"
        case 90...: genZ ? "lock in fr fr" : "Go all in"
        case 60...: genZ ? "lock in fr" : "Go deep"
        default: genZ ? "lock in" : "Start focus"
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

            Text(genZ ? "locking in…" : "Focus starting")
                .font(OrtusTheme.Typo.title)

            Text(genZ ? "forgot smth? you can still dip" : "Forgot something? You can still go back.")
                .font(OrtusTheme.Typo.body)
                .foregroundStyle(OrtusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OrtusTheme.spacingLG)

            HStack(spacing: OrtusTheme.spacingMD) {
                Button(genZ ? "nvm" : "Never mind") {
                    focusManager.revertFocusSession()
                }
                .buttonStyle(OrtusPrimaryButtonStyle())

                Button("Skip and focus") {
                    focusManager.skipGracePeriod()
                }
                .buttonStyle(OrtusSecondaryButtonStyle())
                .help("End the cancellation window and lock in this session now")
            }
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

            VStack(spacing: OrtusTheme.spacingSM) {
                Text(focusManager.currentSessionName ?? "Focus")
                    .font(OrtusTheme.Typo.headline)
                BlockedTags(selection: focusManager.activeSelection)
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

            Text(genZ ? "ready to lock in?" : "Ready when you are")
                .font(OrtusTheme.Typo.title)

            // How long and what to block: one decision, one card.
            VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                OrtusDurationSlider(
                    minutes: $manualDuration,
                    range: 15...240,
                    ticks: [15, 30, 60, 90, 120, 180, 240],
                    step: 15
                )
                Rectangle().fill(OrtusTheme.hairline).frame(height: 1)
                ModePicker(selection: $focusManager.manualSelection, boxed: false)
            }
            .ortusCard()

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

// MARK: - Blocked tags

/// What a focus session is blocking: brand mark plus name. Deliberately not
/// button-shaped (flat, recessed, square-ish corners) so it never reads as an action.
private struct BlockedTags: View {
    let selection: BlockSelection

    private struct Item: Identifiable { let id: String; let glyph: String; let name: String; let isApp: Bool }

    /// One tag per preset the selection touches (Gmail, Slack), then one per other website or app.
    private var items: [Item] {
        var items: [Item] = []
        var websites = selection.websites
        var apps = selection.applications
        for preset in BlockingPreset.all where selection.contains(preset) {
            let name = preset.id == "slack" && !selection.fullyContains(preset)
                ? (selection.blocksSlack ? "Slack app" : "Slack website") : preset.title
            items.append(Item(id: preset.id, glyph: preset.id, name: name, isApp: false))
            websites.removeAll { preset.selection.websites.contains($0) }
            apps.removeAll { app in preset.selection.applications.contains { $0.id == app.id } }
        }
        items += websites.map { Item(id: $0, glyph: BrandGlyph.websiteID(for: $0) ?? "", name: $0, isApp: false) }
        items += apps.map { Item(id: $0.id, glyph: BrandGlyph.applicationID(for: $0) ?? "", name: $0.name, isApp: true) }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let items = items
        FlowLayout(spacing: 6, centered: true) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    glyph(item).opacity(0.75)
                    Text(item.name).font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusSM / 2, style: .continuous).fill(Color.primary.opacity(0.05)))
            }
        }
        .frame(maxWidth: 320)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Blocked: " + items.map(\.name).joined(separator: ", "))
    }

    @ViewBuilder private func glyph(_ item: Item) -> some View {
        if item.glyph.isEmpty && item.isApp {
            Image(systemName: "app").resizable().scaledToFit().frame(width: 12, height: 12).foregroundStyle(OrtusTheme.ink)
        } else {
            BrandGlyph(id: item.glyph, size: 12)
        }
    }
}
