import SwiftUI

struct ChatView: View {
    @EnvironmentObject var claudeService: ClaudeService
    @EnvironmentObject var slackService: SlackService
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            if !claudeService.isConfigured || !slackService.isConnected {
                OrtusEmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "AI chat",
                    message: "To ask AI about your Slack workspace, add a Claude API key and connect Slack in Settings. Focus mode works without this"
                )
            } else if claudeService.messages.isEmpty {
                OrtusEmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "Ask about Slack",
                    message: "Ask what's happening in channels, search messages, or check on conversations"
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
                LazyVStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                    ForEach(claudeService.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if claudeService.isProcessing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Thinking")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, OrtusTheme.spacingMD)
                        .id("loading")
                    }
                }
                .padding(OrtusTheme.spacingMD)
            }
            .onChange(of: claudeService.messages.count) { _ in
                withAnimation {
                    if let last = claudeService.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: claudeService.isProcessing) { _ in
                if claudeService.isProcessing {
                    withAnimation {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: OrtusTheme.spacingSM) {
            if !claudeService.messages.isEmpty {
                Button {
                    claudeService.clearConversation()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear conversation")
            }

            TextField("What would you like to know?", text: $inputText)
                .textFieldStyle(OrtusTextFieldStyle())
                .onSubmit { sendMessage() }
                .disabled(!claudeService.isConfigured || !slackService.isConnected)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? OrtusTheme.accent : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Send message")
        }
        .ortusFloatingToolbar()
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && claudeService.isConfigured
        && slackService.isConnected
        && !claudeService.isProcessing
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canSend else { return }
        inputText = ""
        Task {
            await claudeService.sendMessage(text)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: OrtusTheme.spacingXS) {
                Text(renderMarkdown(message.content))
                    .font(.body)
                    .textSelection(.enabled)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, OrtusTheme.spacingMD)
            .padding(.vertical, OrtusTheme.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous)
                    .fill(message.role == .user ? OrtusTheme.accentSoft : OrtusTheme.cardFill)
            )
            .clipShape(RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous))

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private func renderMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
