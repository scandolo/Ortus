import SwiftUI
import OrtusCore

struct FocusView: View {
    @EnvironmentObject var focusManager: FocusManager
    @EnvironmentObject var router: PanelRouter
    @Environment(\.snapshotState) private var snapshotState
    @AppStorage("genZMode") private var genZ = false
    @AppStorage("didStartFocusSession") private var didStartFocusSession = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts "+15 min" presses, to give each one a springy press reaction.
    @State private var extensions = 0
    @State private var manualDuration: Double = 90
    /// Drives "ends 15:24". A timer kept in state, because TimelineView froze in the
    /// menu bar panel once it had been closed and reopened.
    @State private var now = Date()
    @State private var clock = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // During a session, a browser problem sits on top, where it bites.
                        ClosingBrowserRow(service: focusManager.websites,
                                          showSetupProblem: focusManager.isInFocus && !focusManager.activeSelection.websites.isEmpty
                                              && focusManager.websites.connectedBrowsers.isEmpty && snapshotState != "browser-connected")
                        if inGracePeriod {
                            gracePeriodState
                        } else if focusManager.isInFocus {
                            activeFocusState
                        } else {
                            idleState
                        }
                    }
                    .padding(OrtusTheme.spacingMD)
                    // The grace countdown sits in the middle of the panel, not at the top.
                    .frame(maxWidth: .infinity, minHeight: inGracePeriod ? proxy.size.height : nil, alignment: .leading)
                }
            }
            footer
        }
    }

    // MARK: - Footer

    /// The primary action stays pinned and visible, like "Add schedule".
    @ViewBuilder private var footer: some View {
        if inGracePeriod {
            // An exception to "the safe choice is primary": the user just chose to lock in,
            // so locking in now is the main action and backing out the secondary one.
            HStack(spacing: OrtusTheme.spacingSM) {
                Button(genZ ? "nvm" : "Never mind") { focusManager.revertFocusSession() }
                    .buttonStyle(OrtusSecondaryButtonStyle(fullWidth: true))
                Button(genZ ? "lock in now" : "Lock in now") { focusManager.skipGracePeriod() }
                    .buttonStyle(OrtusPrimaryButtonStyle(fullWidth: true))
                    .help("End the cancellation window and lock in this session now")
            }
            .padding([.horizontal, .bottom], OrtusTheme.spacingMD)
        } else if !focusManager.isInFocus {
            VStack(spacing: OrtusTheme.spacingSM) {
                if blocksNothing {
                    // A locked session that blocks nothing is the worst first impression.
                    Button("Set up website blocking") { router.modal = .browserSetup }
                        .buttonStyle(OrtusPrimaryButtonStyle(size: .large, fullWidth: true))
                    Button(genZ ? "start anyway fr" : "Start anyway") { requestStart() }
                        .buttonStyle(OrtusGhostButtonStyle())
                } else {
                    Button(startLabel) { requestStart() }
                        .buttonStyle(OrtusPrimaryButtonStyle(size: .large, sun: true, fullWidth: true))
                        .disabled(focusManager.manualSelection.isEmpty)
                }
            }
            .padding([.horizontal, .bottom], OrtusTheme.spacingMD)
        }
    }

    private var inGracePeriod: Bool {
        focusManager.isInFocus && focusManager.isInGracePeriod
    }

    /// The chosen mode blocks websites, but no browser is connected to block them.
    private var needsBrowser: Bool {
        let connected = !focusManager.websites.connectedBrowsers.isEmpty && !(snapshotState?.hasPrefix("no-browser") ?? false)
            || snapshotState == "browser-connected"
        return !focusManager.manualSelection.websites.isEmpty && !connected
    }

    /// A websites-only mode blocks nothing until a browser is connected.
    private var blocksNothing: Bool {
        needsBrowser && focusManager.manualSelection.applications.isEmpty
    }

    /// The first session states the lock once, before it starts. That session then skips
    /// the 30 second grace window: the modal already was the moment to back out.
    private func requestStart() {
        guard didStartFocusSession else {
            router.modal = .focusIntro(selection: focusManager.manualSelection, minutes: manualDuration) {
                startSession(skipGrace: true)
            }
            return
        }
        startSession()
    }

    private func startSession(skipGrace: Bool = false) {
        didStartFocusSession = true
        focusManager.startFocusSession(name: "Focus", duration: manualDuration * 60)
        if skipGrace, focusManager.isInGracePeriod { focusManager.skipGracePeriod() }
    }

    /// "Lock in · 90 min". Gen Z mode keeps its own words.
    private var startLabel: String {
        let length = Self.lengthLabel(minutes: manualDuration)
        guard genZ else { return "Lock in · \(length)" }
        let words = switch manualDuration {
        case 180...: "start winter arc"
        case 90...: "lock in fr fr"
        case 60...: "lock in fr"
        default: "lock in"
        }
        return "\(words) · \(length)"
    }

    /// "45 min", "90 min", "2 h", "2 h 30".
    static func lengthLabel(minutes: Double) -> String {
        let m = Int(minutes)
        if m < 120 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60)"
    }

    // MARK: - Grace Period

    private var gracePeriodState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            if let graceEnd = focusManager.gracePeriodEndTime {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let remaining = max(0, graceEnd.timeIntervalSince(context.date))
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(Int(ceil(remaining)))")
                            .font(OrtusTheme.Typo.countdown)
                            .tracking(-5)
                            .monospacedDigit()
                            .foregroundStyle(OrtusTheme.accent)
                            .accessibilityLabel("\(Int(ceil(remaining))) seconds to change your mind")
                        Text(genZ ? "forgot smth?" : "Changed your mind?")
                            .font(OrtusTheme.Typo.titleSmall).tracking(-1)
                        Text(genZ ? "you can still dip for 30s. then it's locked till \(endTimeLabel)."
                                  : "You have 30 seconds. Then it's locked until \(endTimeLabel).")
                            .font(OrtusTheme.Typo.body)
                            .foregroundStyle(OrtusTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        OrtusLineProgress(fraction: remaining / 30)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var endTimeLabel: String {
        (focusManager.focusEndTime ?? Date()).formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Active Focus

    private var hasSessionProblem: Bool {
        focusManager.websites.closingBrowser != nil || snapshotState == "closing-browser"
            || (!focusManager.activeSelection.websites.isEmpty && focusManager.websites.connectedBrowsers.isEmpty && snapshotState != "browser-connected")
    }

    private var activeFocusState: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let endTime = focusManager.focusEndTime {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, endTime.timeIntervalSince(context.date))
                    let total = totalSessionDuration(endingAt: endTime)
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                OrtusIcon(.locked, size: 14)
                                Text("Locked in · \(focusManager.currentSessionName ?? "Focus")".uppercased())
                                    .font(OrtusFont.text(12, .bold)).tracking(1.3)
                            }
                            .foregroundStyle(OrtusTheme.accent)
                            Text(remaining > 0 ? Self.formatDuration(remaining) : (genZ ? "wrapping up" : "Ending"))
                                .font(OrtusFont.display(hasSessionProblem ? 92 : 104))
                                .tracking(-5)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .contentTransition(.numericText(value: remaining))
                                .accessibilityLabel("\(Self.spokenDuration(remaining)) left")
                        }
                        .padding(.top, hasSessionProblem ? 4 : 18)

                        VStack(alignment: .leading, spacing: 8) {
                            OrtusLineProgress(fraction: total > 0 ? 1 - remaining / total : 0)
                            HStack {
                                Spacer()
                                Text("ends \(endTime.formatted(date: .omitted, time: .shortened))")
                                    .contentTransition(.numericText(value: endTime.timeIntervalSince1970))
                            }
                            .font(OrtusTheme.Typo.caption)
                            .foregroundStyle(OrtusTheme.textMuted)
                        }
                    }
                    // Only a new end time animates (+15 min): the digits roll up and the line
                    // eases back. The per-second tick doesn't change endTime, so it never animates.
                    .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.2), value: endTime)
                }
            }

            let items = BlockedItem.all(in: focusManager.activeSelection)
            if !items.isEmpty {
                HStack(spacing: 12) {
                    BlockedStack(items: items, ground: OrtusTheme.canvas, size: 30, limit: 6, showsMore: false)
                    Text(items.count == 1 ? items[0].name : "\(items.count) blocked")
                        .font(OrtusFont.text(14, .semibold))
                }
                .contentShape(Rectangle())
                .help(items.map(\.name).joined(separator: ", "))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Blocked: " + items.map(\.name).joined(separator: ", "))
                .padding(.top, 4)
            }

            Button {
                extensions += 1
                focusManager.extendFocus(by: 15 * 60)
            } label: {
                HStack(spacing: 8) {
                    OrtusIcon(.addTime, size: 16)
                    Text("15 min")
                }
            }
            .buttonStyle(OrtusSecondaryButtonStyle(fullWidth: true))
            // A short squeeze, then a spring back past full size.
            .phaseAnimator([1.0, 0.94], trigger: reduceMotion ? 0 : extensions) { button, scale in
                button.scaleEffect(scale)
            } animation: { scale in
                scale < 1 ? .easeOut(duration: 0.07) : .spring(duration: 0.4, bounce: 0.55)
            }
            .help("Add 15 minutes to this session")
            .accessibilityLabel("Add 15 minutes")
            .padding(.top, 4)

            if focusManager.developerModeEnabled {
                Button("End focus (dev)") {
                    focusManager.endFocusSession()
                }
                .buttonStyle(OrtusGhostButtonStyle())
            }
        }
        .padding(.horizontal, 4)
    }

    private func totalSessionDuration(endingAt end: Date) -> TimeInterval {
        if let start = focusManager.focusStartTime {
            return max(end.timeIntervalSince(start), 1)
        }
        return max(end.timeIntervalSinceNow * 2, 60 * 15)
    }

    // MARK: - Idle

    private var idleState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                OrtusMark(width: 46)
                Text(genZ ? "ready to lock in?" : "Ready when you are")
                    .font(OrtusTheme.Typo.title)
                    .tracking(-1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 4)
            .padding(.top, 14)
            .padding(.bottom, 4)

            // How long and what to block: one decision, one card.
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.lengthLabel(minutes: manualDuration))
                        .font(OrtusTheme.Typo.display)
                        .tracking(-1)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: manualDuration))
                    Spacer()
                    Text("ends \(now.addingTimeInterval(manualDuration * 60).formatted(date: .omitted, time: .shortened))")
                        .font(OrtusTheme.Typo.caption)
                        .foregroundStyle(OrtusTheme.textMuted)
                        .onReceive(clock) { now = $0 }
                        .onAppear { now = Date() }
                }
                OrtusDurationSlider(
                    minutes: $manualDuration,
                    range: 15...240,
                    ticks: [15, 30, 60, 90, 120, 180, 240],
                    step: 15
                )
                Rectangle().fill(OrtusTheme.strong).frame(height: 2)
                ModePicker(selection: $focusManager.manualSelection, boxed: false,
                           problem: needsBrowser ? (message: problemMessage, action: { router.modal = .browserSetup }) : nil)
            }
            .ortusCard()
        }
    }

    private var problemMessage: String {
        genZ ? "website blocking's off. connect a browser" : "Website blocking off. Connect a browser"
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

    /// "47 minutes", for VoiceOver.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        guard minutes >= 60 else { return unit(minutes, "minute") }
        let (h, m) = (minutes / 60, minutes % 60)
        return m == 0 ? unit(h, "hour") : "\(unit(h, "hour")) \(unit(m, "minute"))"
    }
}

// MARK: - First session

/// Shown once, at a new user's first Lock in: what this session blocks, how long, and
/// that there's no way out once it starts, drawn from their own targets and length.
struct FocusIntroModal: View {
    @EnvironmentObject var router: PanelRouter
    let selection: BlockSelection
    let minutes: Double
    let onConfirm: () -> Void

    var body: some View {
        let items = BlockedItem.all(in: selection)
        let until = Date().addingTimeInterval(minutes * 60).formatted(date: .omitted, time: .shortened)
        OrtusModal(title: "No end button.", largeTitle: true, onClose: { router.modal = nil }) {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                // What gets blocked: their own apps and websites, names on hover.
                BlockedStack(items: items, ground: OrtusTheme.cardSurface, size: 32, limit: 5)

                // How it goes: locked from the start until the end. Plain text and a
                // line, so the Lock in button below stays the only thing to press.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        OrtusIcon(.locked, size: 15).foregroundStyle(OrtusTheme.accent)
                        Text("\(FocusView.lengthLabel(minutes: minutes)), locked").font(OrtusFont.text(14, .bold)).foregroundStyle(OrtusTheme.text)
                    }
                    OrtusLineProgress(fraction: 1, height: 4)
                    HStack {
                        Text("starts now")
                        Spacer()
                        Text("ends \(until)")
                    }
                    .font(OrtusTheme.Typo.meta).foregroundStyle(OrtusTheme.textMuted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Locked for \(Int(minutes)) minutes, from now until \(until)")

                Text("Nothing opens until \(until). For a real emergency, you get one early end a week, in Settings.")
                    .font(OrtusTheme.Typo.callout)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Lock in · \(FocusView.lengthLabel(minutes: minutes))") {
                    router.modal = nil
                    onConfirm()
                }
                .buttonStyle(OrtusPrimaryButtonStyle(size: .large, sun: true, fullWidth: true))
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
