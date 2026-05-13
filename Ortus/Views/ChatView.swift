import SwiftUI

struct ChatView: View {
    @EnvironmentObject var claudeCodeService: ClaudeCodeService
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            if !claudeCodeService.isConfigured {
                OrtusEmptyState(
                    icon: "terminal",
                    title: "Claude Code not found",
                    message: "Install Claude Code (docs.claude.com/claude-code), or set its binary path in Settings, to enable AI chat."
                )
            } else if claudeCodeService.messages.isEmpty {
                OrtusEmptyState(
                    icon: "sparkles",
                    title: "Ask about Slack",
                    message: "Catch up on channels, search messages, or send replies without unblocking Slack"
                )
            } else {
                messageList
            }

            inputBar
        }
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

                    if claudeCodeService.isProcessing {
                        ThinkingPill()
                            .id("loading")
                    }
                }
                .padding(OrtusTheme.spacingMD)
                .animation(.easeOut(duration: 0.22), value: claudeCodeService.messages.count)
            }
            .onChange(of: claudeCodeService.messages.count) {
                withAnimation(.easeOut(duration: 0.22)) {
                    if let last = claudeCodeService.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: claudeCodeService.isProcessing) {
                if claudeCodeService.isProcessing {
                    withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: OrtusTheme.spacingSM) {
            if !claudeCodeService.messages.isEmpty {
                Button {
                    claudeCodeService.clearConversation()
                } label: {
                    Image(systemName: "trash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear conversation")
                .disabled(claudeCodeService.isProcessing)
            }

            TextField("What's happening in Slack?", text: $inputText)
                .textFieldStyle(OrtusTextFieldStyle())
                .onSubmit { sendMessage() }
                .disabled(!claudeCodeService.isConfigured || claudeCodeService.isProcessing)

            if claudeCodeService.isProcessing {
                Button {
                    claudeCodeService.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(OrtusTheme.warning)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .help("Stop")
            } else {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? OrtusTheme.accent : .secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Send message")
            }
        }
        .ortusFloatingToolbar()
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

// MARK: - Thinking Pill

private struct ThinkingPill: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(OrtusTheme.accent)
                            .frame(width: 5, height: 5)
                            .opacity(phase == i ? 1.0 : 0.3)
                    }
                }
                Text("Thinking…")
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(OrtusTheme.hairline, lineWidth: 1))
            .clipShape(Capsule())
            .padding(.leading, 4)
        }
    }
}

// MARK: - Message Row

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.kind {
        case .text:
            textBubble
        case .toolUse:
            toolChip
        case .error:
            errorBubble
        }
    }

    private var textBubble: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.role == .user { Spacer(minLength: 36) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 3) {
                Text(renderMarkdown(message.content))
                    .font(OrtusTheme.Typo.body)
                    .textSelection(.enabled)
                    .foregroundStyle(message.role == .user ? .white : .primary)

                Text(message.timestamp, style: .time)
                    .font(OrtusTheme.Typo.meta)
                    .foregroundStyle(message.role == .user ? Color.white.opacity(0.7) : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Group {
                    if message.role == .user {
                        userBubbleBackground
                    } else {
                        assistantBubbleBackground
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)

            if message.role == .assistant { Spacer(minLength: 36) }
        }
    }

    private var userBubbleBackground: some View {
        RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous)
            .fill(OrtusTheme.accent)
            .overlay(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous)
                    .strokeBorder(OrtusTheme.innerHighlightStrong, lineWidth: 1)
            )
    }

    private var assistantBubbleBackground: some View {
        RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous)
            .fill(OrtusTheme.cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous)
                    .strokeBorder(OrtusTheme.innerHighlight, lineWidth: 1)
            )
    }

    private var toolChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "wrench.adjustable")
                .font(.system(size: 10))
                .foregroundStyle(OrtusTheme.accent)
            Text(message.content)
                .font(OrtusTheme.Typo.meta)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(OrtusTheme.cardSurface))
        .overlay(Capsule().strokeBorder(OrtusTheme.hairline, lineWidth: 1))
        .clipShape(Capsule())
        .padding(.leading, 6)
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
