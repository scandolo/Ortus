import OrtusCore
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var claudeCodeService: ClaudeCodeService
    @EnvironmentObject var router: PanelRouter
    @Environment(\.snapshotState) private var snapshotState
    @AppStorage("didSeeChatIntro") private var didSeeChatIntro = false
    @AppStorage("chatIntroSentToSetup") private var chatIntroSentToSetup = false
    @State private var inputText = ""
    @AppStorage("genZMode") private var genZ = false
    @FocusState private var isInputFocused: Bool
    @State private var isBarHovering = false
    @State private var barWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if !claudeCodeService.isConfigured {
                setupState
            } else {
                if claudeCodeService.messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }
                inputBar
            }
        }
        .onAppear {
            #if DEBUG
            ChatFixtures.applySetup(snapshotState, to: claudeCodeService, router: router)
            #endif
            if ChatFixtures.apply(snapshotState, to: claudeCodeService) { return }
            if snapshotState == "chat-draft" {
                claudeCodeService.messages = [
                    ChatMessage(role: .user, content: "Anything urgent in my email?"),
                    ChatMessage(role: .assistant, content: "Two things: Haroun replied about the contract, and your Lisbon flight moved to 9:40."),
                ]
                inputText = "Go through my Slack DMs from this morning, pull out anything that needs a reply today, and draft short answers I can send when the session ends"
            }
        }
        // The first visit explains what Chat is, set up or not, once detection has
        // settled so it doesn't flip from "Set up agent" to "Get started". Someone sent to
        // setup from it sees it again once Claude Code works, unless they're already chatting.
        .onChange(of: claudeCodeService.isDetecting, initial: true) {
            if !claudeCodeService.isDetecting, !didSeeChatIntro, !chatIntroSentToSetup || claudeCodeService.isConfigured,
               claudeCodeService.messages.isEmpty, snapshotState == nil, router.modal == nil {
                router.modal = .chatIntro
            }
        }
    }

    // MARK: - Empty state

    /// Before Claude Code is found the tab is only the setup, centred, with no text box
    /// to type into yet.
    private var setupState: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            Spacer()
            OrtusIcon(.agent, size: 36)
            Text("Your agent needs Claude Code.")
                .font(OrtusTheme.Typo.titleSmall)
                .tracking(-1)
                .multilineTextAlignment(.center)
            Text("Your agent uses Claude Code on your Mac. Set it up once, then ask from here.")
                .font(OrtusTheme.Typo.callout)
                .foregroundStyle(OrtusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OrtusTheme.spacingLG)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set up agent") { router.modal = .chatSetup }
                .buttonStyle(OrtusPrimaryButtonStyle())
                .padding(.top, OrtusTheme.spacingSM)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(OrtusTheme.spacingMD)
    }

    private var emptyState: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            Spacer()
            OrtusIcon(.agent, size: 36)
            Text(genZ ? "stay locked in,\nstill in the loop" : "Ask your agent.\nNothing opens.")
                .font(OrtusTheme.Typo.titleSmall)
                .tracking(-1)
                .multilineTextAlignment(.center)
            Text(genZ ? "it reads the apps ortus blocks so you don’t have to" : "It reads the apps Ortus blocks, so you don’t have to.")
                .font(OrtusTheme.Typo.callout)
                .foregroundStyle(OrtusTheme.textMuted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(OrtusTheme.spacingMD)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: a chat is short, and a lazy stack kept re-laying out its rows
                // forever in 1.1.15 (selectable text and draft cards resize as they lay out).
                VStack(alignment: .leading, spacing: 14) {
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

    /// One line sits in a bar with the buttons beside the text. Once the draft needs a
    /// second line, the bar opens into a card: the text takes the full width and the
    /// buttons drop to a row underneath.
    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The field keeps its place in both layouts, so switching keeps focus.
            HStack(spacing: 10) {
                if !isExpanded && hasConversation { newChatButton }
                inputField
                if !isExpanded { sendButton }
            }
            .padding(.leading, isExpanded || !hasConversation ? 14 : 10)
            .padding(.trailing, isExpanded ? 14 : 8)
            .padding(.top, isExpanded ? 12 : 8)
            .padding(.bottom, isExpanded ? 0 : 8)

            if isExpanded {
                HStack {
                    if hasConversation { newChatButton }
                    Spacer()
                    sendButton
                }
                .padding([.horizontal, .bottom], 10)
                .padding(.top, 6)
            }
        }
        .frame(minHeight: 50)
        .background(inputBarShape.fill(OrtusTheme.cardSurface))
        .overlay(inputBarShape.strokeBorder(OrtusTheme.text.opacity(isInputFocused ? 1 : isBarHovering ? 0.25 : 0), lineWidth: 2))
        .animation(.easeOut(duration: 0.15), value: isBarHovering)
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
        .padding([.horizontal, .bottom], OrtusTheme.spacingMD)
        .animation(.easeOut(duration: 0.18), value: isInputFocused)
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
            .disabled(!claudeCodeService.isConfigured)
    }

    private var newChatButton: some View {
        Button {
            claudeCodeService.clearConversation()
        } label: {
            OrtusIcon(.edit, size: 15)
                .foregroundStyle(OrtusTheme.textMuted)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(OrtusPressableStyle(cornerRadius: 8))
        .help("New chat")
        .accessibilityLabel("New chat")
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
        let buttons: CGFloat = (hasConversation ? 28 + 10 : 0) + 34 + 10
        let insets: CGFloat = (hasConversation ? 10 : 14) + 8
        let textWidth = (inputText as NSString).size(withAttributes: [.font: OrtusFont.nsText(15)]).width
        // Some slack so the card opens before the field itself starts to wrap.
        return textWidth > barWidth - buttons - insets - 8
    }

    private var inputBarShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
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

    var body: some View {
        Button(action: action) {
            OrtusIcon(.send, size: 15)
                .foregroundStyle(canSend ? OrtusTheme.onStrong : OrtusTheme.textMuted)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(canSend ? OrtusTheme.strong : OrtusTheme.cardChip))
        }
        .buttonStyle(OrtusPressableStyle(cornerRadius: 10))
        .disabled(!canSend)
        .help("Send message")
        .accessibilityLabel("Send")
        .animation(.easeOut(duration: 0.15), value: canSend)
    }
}

private struct ChatStopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OrtusIcon(.stop, size: 14)
                .foregroundStyle(OrtusTheme.onStrong)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(OrtusTheme.strong))
        }
        .buttonStyle(OrtusPressableStyle(cornerRadius: 10))
        .help("Stop")
        .accessibilityLabel("Stop")
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
                        HStack(spacing: 7) {
                            OrtusIcon(.chevronRight, size: 11)
                                .rotationEffect(.degrees(isOpen ? 90 : 0))
                            Text(summary)
                            if activity.hasProblem {
                                OrtusProblemIcon(size: 16)
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
                .padding(.vertical, 2)
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
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(OrtusTheme.text)
                            .frame(width: 7, height: 7)
                            .opacity([1.0, 0.5, 0.25][(i - phase + 3) % 3])
                    }
                }
                Text(activity.progress + "…")
                    .foregroundStyle(OrtusTheme.textMuted)
                // A count after a few seconds shows it hasn't stalled.
                if elapsed >= 3 {
                    Text("\(elapsed)s").foregroundStyle(OrtusTheme.textMuted).monospacedDigit()
                }
            }
            .font(OrtusTheme.Typo.caption)
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(activity.steps) { step in
                HStack(alignment: .center, spacing: 8) {
                    if step.status == .failed {
                        OrtusProblemIcon(size: 14)
                    }
                    Text(step.status == .failed ? "\(step.progress) failed" : step.title)
                        .italic(step.kind != .tool)
                        // Thinking reads quieter than tool steps (Archivo has no italic).
                        .foregroundStyle(OrtusTheme.textMuted.opacity(step.kind != .tool ? 0.7 : 1))
                        .lineLimit(3)
                }
            }
            if let finished = activity.finishedAt {
                let seconds = max(1, Int(finished.timeIntervalSince(activity.startedAt).rounded()))
                Text(activity.wasStopped ? "Stopped after \(seconds)s" : "Done in \(seconds)s")
                    .foregroundStyle(OrtusTheme.textMuted)
            }
        }
        .font(OrtusTheme.Typo.caption)
        .padding(.vertical, 2)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle().fill(OrtusTheme.line).frame(width: 2)
        }
        .padding(.leading, 5)
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
                Spacer(minLength: 60)
                // Verbatim: an email or a web address you typed stays plain text, not a link.
                Text(verbatim: message.content)
                    .font(OrtusFont.text(15, .medium))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .foregroundStyle(OrtusTheme.onStrong)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(OrtusTheme.strong))
                    .help(message.timestamp.formatted(date: .omitted, time: .shortened))
            }
        } else {
            // Answers read as a document across the panel, not a bubble.
            ChatAnswerView(text: message.content, messageID: message.id)
                .help(message.timestamp.formatted(date: .omitted, time: .shortened))
        }
    }

    private var errorBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            OrtusProblemIcon(size: 18)
            Text(message.content)
                .font(OrtusTheme.Typo.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous).fill(OrtusTheme.cardSurface))
    }
}

// MARK: - First-run intro

/// Shown the first time Chat opens: what it is, what it uses, and that it asks before acting.
struct ChatIntroModal: View {
    @EnvironmentObject var router: PanelRouter
    @EnvironmentObject var claudeCodeService: ClaudeCodeService
    @AppStorage("didSeeChatIntro") private var didSeeChatIntro = false
    @AppStorage("chatIntroSentToSetup") private var chatIntroSentToSetup = false

    var body: some View {
        OrtusModal(title: "Your agent while you focus", largeTitle: true, onClose: close) {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                Text("Ask about the apps Ortus blocks, without opening them.")
                    .font(OrtusTheme.Typo.callout).foregroundStyle(OrtusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                OrtusGroup {
                    OrtusListRow(title: "Runs on Claude Code",
                                 subtitle: claudeCodeService.isConfigured ? "Already on this Mac, so there’s nothing to set up." : "Install it once, and your agent uses it from then on.") {
                        OrtusIcon(.terminal, size: 18)
                    } trailing: { EmptyView() }
                    OrtusGroupDivider()
                    OrtusListRow(title: "Uses your connectors", subtitle: "Whatever you connected to Claude Code.") {
                        OrtusIcon(.link, size: 18)
                    } trailing: { EmptyView() }
                    OrtusGroupDivider()
                    OrtusListRow(title: "Asks before acting", subtitle: "It checks with you before it sends or changes anything.") {
                        OrtusIcon(.shield, size: 18)
                    } trailing: { EmptyView() }
                }
                .overlay(RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous).strokeBorder(OrtusTheme.line, lineWidth: 1))
                HStack {
                    Spacer()
                    if claudeCodeService.isConfigured {
                        Button("Get started", action: close).buttonStyle(OrtusPrimaryButtonStyle())
                    } else {
                        Button("Set up agent") {
                            chatIntroSentToSetup = true
                            router.modal = .chatSetup
                        }
                        .buttonStyle(OrtusPrimaryButtonStyle())
                    }
                }
            }
        }
    }

    private func close() {
        didSeeChatIntro = true
        router.modal = nil
    }
}
