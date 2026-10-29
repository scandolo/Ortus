import SwiftUI
import OrtusCore

struct FocusView: View {
    @EnvironmentObject var focusManager: FocusManager
    @EnvironmentObject var router: PanelRouter
    @Environment(\.snapshotState) private var snapshotState
    @AppStorage("genZMode") private var genZ = false
    @AppStorage("didStartFocusSession") private var didStartFocusSession = false
    @State private var manualDuration: Double = 90

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(spacing: OrtusTheme.spacingLG) {
                // Before a session, the setup problem sits on the mode it affects (idle state).
                if focusManager.isInFocus, !focusManager.activeSelection.websites.isEmpty,
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
                VStack(spacing: OrtusTheme.spacingSM) {
                    if blocksNothing {
                        // A locked session that blocks nothing is the worst first impression.
                        Button { router.modal = .browserSetup } label: {
                            Text("Set up website blocking").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OrtusPrimaryButtonStyle())
                        Button("Start anyway") { requestStart() }
                            .buttonStyle(OrtusGhostButtonStyle())
                    } else {
                        Button { requestStart() } label: {
                            Text(startLabel).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OrtusPrimaryButtonStyle())
                        .disabled(focusManager.manualSelection.isEmpty)
                    }
                }
                .padding(.horizontal, OrtusTheme.spacingMD)
                .padding(.bottom, OrtusTheme.spacingSM)
            }
        }
    }

    /// The chosen mode blocks websites, but no browser is connected to block them.
    private var needsBrowser: Bool {
        let connected = !focusManager.websites.connectedBrowsers.isEmpty && snapshotState != "no-browser"
        return !focusManager.manualSelection.websites.isEmpty && !connected
    }

    /// A websites-only mode blocks nothing until a browser is connected.
    private var blocksNothing: Bool {
        needsBrowser && focusManager.manualSelection.applications.isEmpty
    }

    /// The first session explains the lock before it starts.
    private func requestStart() {
        guard didStartFocusSession else {
            router.modal = .focusIntro(selection: focusManager.manualSelection, minutes: manualDuration) { startSession() }
            return
        }
        startSession()
    }

    private func startSession() {
        didStartFocusSession = true
        focusManager.startFocusSession(name: "Focus", duration: manualDuration * 60)
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
                Text(Self.formatDuration(remaining))
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
                if needsBrowser { browserProblem }
            }
            .ortusCard()

        }
    }

    /// What the missing browser means for this mode. When it would block nothing, the
    /// start button becomes the fix, so the line only explains.
    private var browserProblem: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill").foregroundStyle(OrtusTheme.warning)
            Text(blocksNothing ? "Blocks nothing until your browser is connected" : "Websites stay open until your browser is connected")
                .font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if !blocksNothing {
                Button("Set up") { router.modal = .browserSetup }.buttonStyle(OrtusRowButtonStyle())
            }
        }
    }

    // MARK: - Helpers

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - First session

/// Shown before the first session: what this session will do, and that there's no
/// way out once it starts, drawn from the user's own targets and duration.
struct FocusIntroModal: View {
    @EnvironmentObject var router: PanelRouter
    let selection: BlockSelection
    let minutes: Double
    let onConfirm: () -> Void

    var body: some View {
        let items = BlockedItem.all(in: selection)
        let until = Date().addingTimeInterval(minutes * 60).formatted(date: .omitted, time: .shortened)
        OrtusModal(title: "No end button", onClose: { router.modal = nil }) {
            VStack(spacing: OrtusTheme.spacingLG) {
                // What gets blocked: their own apps and websites, names on hover.
                HStack(spacing: OrtusTheme.spacingSM) {
                    BlockedFacepile(items: items, limit: 5, size: 34, ring: OrtusTheme.cardSurface)
                    if items.count > 5 {
                        Text("+\(items.count - 5)").font(OrtusTheme.Typo.badge).foregroundStyle(OrtusTheme.textMuted)
                    }
                }
                .help(items.map(\.name).joined(separator: ", "))

                // How it goes: a short window to undo, then locked until the end.
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        // Open while you can still undo, solid once locked.
                        Capsule().strokeBorder(OrtusTheme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).frame(width: 64)
                            .overlay(Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .bold)).foregroundStyle(OrtusTheme.accentInk))
                        Capsule().fill(OrtusTheme.accentSoft)
                            .overlay(Label("\(Int(minutes)) min", systemImage: "lock.fill").font(OrtusTheme.Typo.badge).foregroundStyle(OrtusTheme.accentInk))
                    }
                    .frame(height: 28)
                    HStack {
                        Text("30 s to undo")
                        Spacer()
                        Text("Ends \(until)")
                    }
                    .font(OrtusTheme.Typo.meta).foregroundStyle(OrtusTheme.textMuted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("30 seconds to undo, then locked for \(Int(minutes)) minutes, until \(until)")

                Text("For real emergencies, one early end a week in Settings.")
                    .font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
                    .multilineTextAlignment(.center)

                Button("Understood, start") {
                    router.modal = nil
                    onConfirm()
                }
                .buttonStyle(OrtusPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Blocked tags

/// One mark per preset the selection touches (Gmail, Slack), then one per other website or app.
private struct BlockedItem: Identifiable {
    let id: String; let glyph: String; let name: String; let isApp: Bool

    static func all(in selection: BlockSelection) -> [BlockedItem] {
        var items: [BlockedItem] = []
        var websites = selection.websites
        var apps = selection.applications
        for preset in BlockingPreset.all where selection.contains(preset) {
            let name = preset.id == "slack" && !selection.fullyContains(preset)
                ? (selection.blocksSlack ? "Slack app" : "Slack website") : preset.title
            items.append(BlockedItem(id: preset.id, glyph: preset.id, name: name, isApp: false))
            websites.removeAll { preset.selection.websites.contains($0) }
            apps.removeAll { app in preset.selection.applications.contains { $0.id == app.id } }
        }
        items += websites.map { BlockedItem(id: $0, glyph: BrandGlyph.websiteID(for: $0) ?? "", name: $0, isApp: false) }
        items += apps.map { BlockedItem(id: $0.id, glyph: BrandGlyph.applicationID(for: $0) ?? "", name: $0.name, isApp: true) }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Overlapping brand marks.
private struct BlockedFacepile: View {
    let items: [BlockedItem]
    /// Marks shown; the rest are left to a count or the names next to it.
    var limit = 6
    var size: CGFloat = 24
    /// The gap between marks: the colour of whatever they sit on.
    var ring = OrtusTheme.canvas

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(items.prefix(limit).enumerated()), id: \.element.id) { index, item in
                glyph(item).opacity(0.85)
                    .frame(width: size, height: size)
                    .background(Circle().fill(OrtusTheme.cardSurface))
                    .overlay(Circle().strokeBorder(OrtusTheme.hairline, lineWidth: 1))
                    .padding(2)
                    .background(Circle().fill(ring))
                    .zIndex(Double(-index))
            }
        }
    }

    @ViewBuilder private func glyph(_ item: BlockedItem) -> some View {
        if item.glyph.isEmpty && item.isApp {
            Image(systemName: "app").resizable().scaledToFit().frame(width: size / 2, height: size / 2).foregroundStyle(OrtusTheme.ink)
        } else {
            BrandGlyph(id: item.glyph, size: size / 2)
        }
    }
}

/// What a focus session is blocking: overlapping brand marks plus a count, on one
/// line however long the list. Names show on hover.
private struct BlockedTags: View {
    let selection: BlockSelection

    var body: some View {
        let items = BlockedItem.all(in: selection)
        let names = items.map(\.name).joined(separator: ", ")
        if !items.isEmpty {
            HStack(spacing: OrtusTheme.spacingSM) {
                BlockedFacepile(items: items)
                Text(items.count == 1 ? items[0].name : "\(items.count) blocked")
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(OrtusTheme.textMuted)
            }
            .help(names)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Blocked: " + names)
        }
    }
}
