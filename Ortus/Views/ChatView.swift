import OrtusCore
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var claudeCodeService: ClaudeCodeService
    @EnvironmentObject var router: PanelRouter
    @Environment(\.snapshotState) private var snapshotState
    @AppStorage("didSeeChatIntro") private var didSeeChatIntro = false
    @State private var inputText = ""
    @AppStorage("genZMode") private var genZ = false
    @FocusState private var isInputFocused: Bool
    @State private var isBarHovering = false
    @State private var barWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if !claudeCodeService.isConfigured {
                OrtusEmptyState(
                    icon: "sparkles",
                    title: "Chat needs Claude Code",
                    message: "Install Claude Code from docs.claude.com/claude-code, then check again in Settings."
                )
            } else if claudeCodeService.messages.isEmpty {
                emptyState
            } else {
                messageList
            }

            inputBar
        }
        .onAppear {
            if ChatFixtures.apply(snapshotState, to: claudeCodeService) { return }
            if snapshotState == "chat-draft" {
                claudeCodeService.messages = [
                    ChatMessage(role: .user, content: "Anything urgent in my email?"),
                    ChatMessage(role: .assistant, content: "Two things: Haroun replied about the contract, and your Lisbon flight moved to 9:40."),
                ]
                inputText = "Go through my Slack DMs from this morning, pull out anything that needs a reply today, and draft short answers I can send when the session ends"
            }
        }
        // Chat works with no setup, so the first visit explains what it is instead.
        .onChange(of: claudeCodeService.isConfigured, initial: true) {
            if claudeCodeService.isConfigured, !didSeeChatIntro, snapshotState == nil, router.modal == nil {
                router.modal = .chatIntro
            }
        }
    }

    // MARK: - Empty state

    private let suggestions = ["Catch me up on Slack", "Anything urgent in my email?", "What’s on my calendar today?"]

    private var emptyState: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 40, weight: .light)).foregroundStyle(OrtusTheme.accent)
            Text(genZ ? "stay locked in, still in the loop" : "Stay in focus, still get answers").font(OrtusTheme.Typo.title).multilineTextAlignment(.center)
            VStack(spacing: OrtusTheme.spacingSM) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { inputText = suggestion; isInputFocused = true } label: {
                        Text(suggestion).font(OrtusTheme.Typo.body)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(OrtusTheme.cardSurface))
                            .overlay(Capsule().strokeBorder(OrtusTheme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(OrtusPressableStyle(cornerRadius: 20))
                }
            }
            .padding(.top, OrtusTheme.spacingXS)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(OrtusTheme.spacingMD)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                    ForEach(claudeCodeService.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    }
                }
                .padding(OrtusTheme.spacingMD)
                .animation(.easeOut(duration: 0.22), value: claudeCodeService.messages.count)
            }
            // Also follows the activity row and the answer as they grow in place.
            .onChange(of: claudeCodeService.messages.last) {
                withAnimation(.easeOut(duration: 0.22)) {
                    if let last = claudeCodeService.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Bar

    /// One line sits in a capsule with the buttons beside the text. Once the draft
    /// needs a second line, the bar opens into a card: the text takes the full width
    /// and the buttons drop to a row underneath.
    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The field keeps its place in both layouts, so switching keeps focus.
            HStack(spacing: OrtusTheme.spacingSM) {
                if !isExpanded && hasConversation { newChatButton }
                inputField
                if !isExpanded { sendButton }
            }
            .padding(.leading, isExpanded || !hasConversation ? OrtusTheme.spacingMD : 6)
            .padding(.trailing, isExpanded ? OrtusTheme.spacingMD : 6)
            .padding(.top, 6)
            .padding(.bottom, isExpanded ? 0 : 6)

            if isExpanded {
                HStack {
                    if hasConversation { newChatButton }
                    Spacer()
                    sendButton
                }
                .padding([.horizontal, .bottom], 6)
                .padding(.top, 2)
            }
        }
        .frame(minHeight: OrtusTheme.controlHeight)
        .background(inputBarBackground)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { barWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { barWidth = proxy.size.width }
        })
        // The whole bar is the field: clicks on its padding focus the text box.
        .contentShape(inputBarShape)
        .onTapGesture { isInputFocused = true }
        .onHover { hovering in
            isBarHovering = hovering
            // The whole bar behaves like the text field, cursor included.
            if hovering { NSCursor.iBeam.push() } else { NSCursor.pop() }
        }
        .padding(.horizontal, OrtusTheme.spacingMD)
        .padding(.bottom, OrtusTheme.spacingSM)
        .animation(.easeOut(duration: 0.18), value: isInputFocused)
        .animation(.easeOut(duration: 0.18), value: isBarHovering)
    }

    // Wraps instead of scrolling sideways, and grows to six lines before it
    // scrolls. Return still sends.
    private var inputField: some View {
        TextField("", text: $inputText, prompt: Text(genZ ? "spill…" : "What do you need?").foregroundStyle(OrtusTheme.textMuted), axis: .vertical)
            .textFieldStyle(.plain)
            .font(OrtusTheme.Typo.body)
            .lineLimit(1...6)
            .padding(.vertical, 6)
            .focused($isInputFocused)
            .onSubmit { sendMessage() }
            .disabled(!claudeCodeService.isConfigured || claudeCodeService.isProcessing)
    }

    private var newChatButton: some View {
        Button {
            claudeCodeService.clearConversation()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.callout)
                .foregroundStyle(OrtusTheme.textMuted)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(OrtusPressableStyle(cornerRadius: 14))
        .help("New chat")
        .disabled(claudeCodeService.isProcessing)
    }

    @ViewBuilder private var sendButton: some View {
        if claudeCodeService.isProcessing {
            ChatStopButton(action: { claudeCodeService.stop() })
        } else {
            ChatSendButton(canSend: canSend, action: sendMessage)
        }
    }

    private var hasConversation: Bool { !claudeCodeService.messages.isEmpty }

    /// True once the draft no longer fits on one line beside the buttons. Measured
    /// against the one-line layout, so the card doesn't flip back when it widens.
    private var isExpanded: Bool {
        if inputText.contains("\n") { return true }
        guard barWidth > 0, !inputText.isEmpty else { return false }
        let buttons: CGFloat = (hasConversation ? 2 : 1) * (28 + OrtusTheme.spacingSM)
        let insets: CGFloat = (hasConversation ? 6 : OrtusTheme.spacingMD) + 6
        let textWidth = (inputText as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        // Some slack so the card opens before the field itself starts to wrap.
        return textWidth > barWidth - buttons - insets - 8
    }

    /// A capsule on one line. The card keeps the same end radius, so a long draft
    /// reads as a soft rounded rectangle rather than a tall stadium.
    private var inputBarShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: OrtusTheme.controlHeight / 2, style: .continuous)
    }

    private var inputBarBackground: some View {
        ZStack {
            // While typing, a soft amber halo just outside the edge, not a heavy ring.
            inputBarShape
                .stroke(OrtusTheme.accent.opacity(isInputFocused ? 0.14 : 0), lineWidth: 7)
            inputBarShape
                .fill(OrtusTheme.cardSurface)
                .shadow(
                    color: .black.opacity(isBarHovering ? 0.16 : 0.12),
                    radius: isBarHovering ? 16 : 14,
                    y: isBarHovering ? 5 : 4
                )
            // A thin top highlight lifts the surface in dark mode.
            inputBarShape
                .strokeBorder(LinearGradient(colors: [OrtusTheme.innerHighlight, .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
            inputBarShape
                .strokeBorder(
                    isInputFocused ? OrtusTheme.accent.opacity(0.55) : isBarHovering ? OrtusTheme.accent.opacity(0.35) : OrtusTheme.hairline,
                    lineWidth: 1
                )
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && claudeCodeService.isConfigured
        && !claudeCodeService.isProcessing
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canSend else { return }
        inputText = ""
        claudeCodeService.sendMessage(text)
    }
}

// MARK: - Send / Stop Buttons

private struct ChatSendButton: View {
    let canSend: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(canSend ? OrtusTheme.onAccent : OrtusTheme.textMuted)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(
                            canSend
                                ? (isHovering ? OrtusTheme.accentInkHover : OrtusTheme.accentInk)
                                : Color.primary.opacity(0.08)
                        )
                        // A soft sheen from the top gives the filled button some depth.
                        .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(canSend ? 0.2 : 0), .clear], startPoint: .top, endPoint: .center)))
                )
                .overlay(
                    Circle().strokeBorder(
                        canSend ? OrtusTheme.innerHighlightStrong : .clear,
                        lineWidth: 1
                    )
                )
                .shadow(
                    color: canSend ? OrtusTheme.accent.opacity(isHovering ? 0.55 : 0.30) : .clear,
                    radius: isHovering ? 8 : 4,
                    y: 1
                )
                .scaleEffect(canSend && isHovering ? 1.08 : 1.0)
        }
        .buttonStyle(OrtusPressableStyle(highlight: false))
        .disabled(!canSend)
        .help("Send message")
        .animation(.easeOut(duration: 0.18), value: isHovering)
        .animation(.easeOut(duration: 0.18), value: canSend)
        .onHover { isHovering = $0 }
    }
}

private struct ChatStopButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(OrtusTheme.warning))
                .overlay(
                    Circle().strokeBorder(OrtusTheme.innerHighlightStrong, lineWidth: 1)
                )
                .shadow(
                    color: OrtusTheme.warning.opacity(isHovering ? 0.55 : 0.30),
                    radius: isHovering ? 8 : 4,
                    y: 1
                )
                .scaleEffect(isHovering ? 1.08 : 1.0)
        }
        .buttonStyle(OrtusPressableStyle(highlight: false))
        .help("Stop")
        .animation(.easeOut(duration: 0.18), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Activity

/// Claude's work for one answer as a single quiet line. While it works, the line
/// names the current step; once done it settles into a summary ("Searched Slack ·
/// 2 steps") that opens into the list of steps. It opens by itself when a step failed.
private struct ActivityRow: View {
    let activity: ChatActivity
    @Environment(\.snapshotState) private var snapshotState
    @State private var isOpen = false

    var body: some View {
        Group {
            if activity.finishedAt == nil {
                liveLine
            } else if let summary = activity.summary {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { isOpen.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(isOpen ? 90 : 0))
                            Text(summary)
                            if activity.hasProblem {
                                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(OrtusTheme.danger)
                            }
                        }
                        .font(OrtusTheme.Typo.caption)
                        .foregroundStyle(OrtusTheme.textMuted)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isOpen ? "Hide steps" : "Show steps")

                    if isOpen { stepList.transition(.opacity) }
                }
            }
        }
        .padding(.leading, 4)
        .onChange(of: activity.hasProblem, initial: true) {
            if activity.hasProblem || snapshotState == "chat-steps" { isOpen = true }
        }
    }

    private var liveLine: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            let elapsed = Int(context.date.timeIntervalSince(activity.startedAt))
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(OrtusTheme.accent)
                            .frame(width: 5, height: 5)
                            .opacity(phase == i ? 1.0 : 0.3)
                    }
                }
                Text(activity.progress + "…")
                    .foregroundStyle(OrtusTheme.textMuted)
                // A count after a few seconds shows it hasn't stalled.
                if elapsed >= 3 {
                    Text("\(elapsed)s").foregroundStyle(OrtusTheme.textMuted.opacity(0.7)).monospacedDigit()
                }
            }
            .font(OrtusTheme.Typo.caption)
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(activity.steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if step.status == .failed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(OrtusTheme.danger)
                    }
                    Text(step.status == .failed ? "\(step.progress) failed" : step.title)
                        .italic(step.kind != .tool)
                        .foregroundStyle(step.kind == .tool ? OrtusTheme.textMuted : OrtusTheme.textMuted.opacity(0.75))
                        .lineLimit(3)
                }
            }
            if let finished = activity.finishedAt {
                let seconds = max(1, Int(finished.timeIntervalSince(activity.startedAt).rounded()))
                Text(activity.wasStopped ? "Stopped after \(seconds)s" : "Done in \(seconds)s")
                    .foregroundStyle(OrtusTheme.textMuted.opacity(0.7))
            }
        }
        .font(OrtusTheme.Typo.caption)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle().fill(OrtusTheme.textMuted.opacity(0.3)).frame(width: 1)
        }
        .padding(.leading, 4)
    }
}

// MARK: - Message Row

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.kind {
        case .text:
            textBubble
        case .activity(let activity):
            ActivityRow(activity: activity)
        case .error:
            errorBubble
        }
    }

    @ViewBuilder private var textBubble: some View {
        if message.role == .user {
            HStack(spacing: 0) {
                Spacer(minLength: 36)
                Text(renderMarkdown(message.content))
                    .font(OrtusTheme.Typo.body)
                    .textSelection(.enabled)
                    .foregroundStyle(OrtusTheme.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(userBubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                    .help(message.timestamp.formatted(date: .omitted, time: .shortened))
            }
        } else {
            // Answers read as a document across the panel, not a bubble.
            ChatAnswerView(text: message.content, messageID: message.id)
                .help(message.timestamp.formatted(date: .omitted, time: .shortened))
        }
    }

    private var userBubbleBackground: some View {
        RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous)
            .fill(OrtusTheme.accentInk)
            .overlay(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous)
                    .strokeBorder(OrtusTheme.innerHighlightStrong, lineWidth: 1)
            )
    }

    private var errorBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(OrtusTheme.danger)
                .symbolRenderingMode(.hierarchical)
            Text(message.content)
                .font(OrtusTheme.Typo.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
                .fill(OrtusTheme.danger.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
                .strokeBorder(OrtusTheme.danger.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous))
    }

    private func renderMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

// MARK: - First-run intro

/// Shown the first time Chat opens: what it is, what it uses, and that it asks before acting.
struct ChatIntroModal: View {
    @EnvironmentObject var router: PanelRouter
    @AppStorage("didSeeChatIntro") private var didSeeChatIntro = false

    var body: some View {
        OrtusModal(title: "Chat while you focus", onClose: close) {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                Text("Ask about the apps Ortus blocks, without opening them.")
                    .font(OrtusTheme.Typo.body).foregroundStyle(OrtusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                OrtusGroup {
                    OrtusListRow(title: "Runs on Claude Code", subtitle: "Already on this Mac, so there is nothing to set up.") {
                        Image(systemName: "terminal")
                    } trailing: { EmptyView() }
                    OrtusGroupDivider()
                    OrtusListRow(title: "Uses your connectors", subtitle: "Slack, Gmail, Calendar: whatever you connected to Claude.") {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                    } trailing: { EmptyView() }
                    OrtusGroupDivider()
                    OrtusListRow(title: "Asks before acting", subtitle: "It checks with you before it sends or changes anything.") {
                        Image(systemName: "checkmark.shield")
                    } trailing: { EmptyView() }
                }
                HStack {
                    Spacer()
                    Button("Get started", action: close).buttonStyle(OrtusPrimaryButtonStyle())
                }
            }
        }
    }

    private func close() {
        didSeeChatIntro = true
        router.modal = nil
    }
}
