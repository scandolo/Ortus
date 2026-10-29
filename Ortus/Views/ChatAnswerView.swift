import OrtusCore
import SwiftUI

/// An assistant answer laid out as a document across the panel width: paragraphs,
/// lists, quotes, code, and cards for messages Claude quoted from Slack, email or a post.
struct ChatAnswerView: View {
    let text: String
    /// The chat message this answer is, so a draft card can find out whether it was sent.
    var messageID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
            ForEach(Array(ChatMarkdown.blocks(text).enumerated()), id: \.offset) { index, block in
                blockView(block, id: "\(messageID)-\(index)")
            }
        }
        .font(OrtusTheme.Typo.body)
        .textSelection(.enabled)
        .tint(OrtusTheme.accentInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    @ViewBuilder private func blockView(_ block: ChatBlock, id: String) -> some View {
        switch block {
        case .paragraph(let text):
            Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            list(items.map { ("•", $0) })
        case .numbered(let items):
            list(items.enumerated().map { ("\($0.offset + 1).", $0.element) })
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1).fill(OrtusTheme.accent).frame(width: 2)
                Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
            }
        case .code(let text):
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OrtusTheme.spacingSM)
                .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusSM, style: .continuous).fill(OrtusTheme.inputSurface))
        case .quote(let quote):
            QuoteCard(quote: quote)
        case .draft(let draft):
            DraftCard(draft: draft, id: id)
        }
    }

    private func list(_ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.0).foregroundStyle(OrtusTheme.textMuted).monospacedDigit()
                    Text(Self.inline(item.1)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, 2)
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

// MARK: - Quote card

/// Messages quoted verbatim, laid out like their source. Slack and posts show each
/// message with its sender and time, a thread in order; email shows the subject,
/// the sender and the body. Long threads keep the first message and the last two.
private struct QuoteCard: View {
    let quote: ChatQuote
    @State private var showsAllReplies = false
    @State private var showsFullEmail = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            header
            if quote.source == "gmail" { email } else { thread }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(OrtusTheme.cardSurface))
        .overlay(shape.strokeBorder(OrtusTheme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    private var header: some View {
        HStack(spacing: 6) {
            BrandGlyph(id: quote.source, size: 12)
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
            if quote.source == "gmail", let time = quote.messages.last?.time {
                Text(ChatQuote.timeLabel(time, now: Date()))
            }
        }
        .font(OrtusTheme.Typo.caption)
        .foregroundStyle(OrtusTheme.textMuted)
    }

    private var title: String {
        switch quote.source {
        case "gmail": "Gmail"
        case "linkedin": "LinkedIn"
        case "x": quote.place.isEmpty ? "X" : quote.place
        default: quote.place.isEmpty ? "Quote" : quote.place
        }
    }

    // MARK: Slack, posts

    @ViewBuilder private var thread: some View {
        let entries = quote.entries
        if entries.count > 4 && !showsAllReplies {
            let hidden = entries[1..<(entries.count - 2)]
            let count = hidden.reduce(0) { total, entry in
                if case .skipped(let n) = entry { total + n } else { total + 1 }
            }
            entryView(entries[0])
            ExpandButton(title: "\(count) more \(count == 1 ? "reply" : "replies")") { showsAllReplies = true }
                .padding(.leading, 29)
            ForEach(Array(entries.suffix(2).enumerated()), id: \.offset) { _, entry in entryView(entry) }
        } else {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in entryView(entry) }
        }
    }

    @ViewBuilder private func entryView(_ entry: ChatQuote.Entry) -> some View {
        switch entry {
        case .skipped(let count):
            // Claude left these out, so there is nothing to open: plain text, not a control.
            Text("\(count) \(count == 1 ? "reply" : "replies") left out")
                .font(OrtusTheme.Typo.caption.italic())
                .foregroundStyle(OrtusTheme.textMuted)
                .padding(.leading, 29)
        case .message(let message):
            HStack(alignment: .top, spacing: 9) {
                avatar(message.from)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(message.from).font(OrtusTheme.Typo.bodyMedium.weight(.semibold))
                        if let time = message.time {
                            Text(ChatQuote.timeLabel(time, now: Date()))
                                .font(OrtusTheme.Typo.meta)
                                .foregroundStyle(OrtusTheme.textMuted)
                        }
                    }
                    if let about = message.about {
                        Text(about).font(OrtusTheme.Typo.meta).foregroundStyle(OrtusTheme.textMuted)
                    }
                    Text(ChatAnswerView.inline(message.text)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func avatar(_ name: String) -> some View {
        Text(name.first.map { String($0).uppercased() } ?? "?")
            .font(OrtusTheme.Typo.badge)
            .foregroundStyle(OrtusTheme.textMuted)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(OrtusTheme.inputSurface))
    }

    // MARK: Email

    @ViewBuilder private var email: some View {
        let messages = quote.messages
        VStack(alignment: .leading, spacing: 4) {
            if !quote.place.isEmpty {
                Text(quote.place).font(OrtusTheme.Typo.bodyMedium.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            // Earlier messages in the thread, one line each.
            ForEach(Array(messages.dropLast().enumerated()), id: \.offset) { _, message in
                Text("\(Self.sender(message.from)): \(message.text)")
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(OrtusTheme.textMuted)
                    .lineLimit(1)
            }
            if let last = messages.last {
                Text(Self.sender(last.from) + (last.to.map { " · to \($0)" } ?? ""))
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(OrtusTheme.textMuted)
                Text(ChatAnswerView.inline(last.text))
                    .lineLimit(showsFullEmail ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                if last.text.count > 240 && !showsFullEmail {
                    ExpandButton(title: "Show more") { showsFullEmail = true }
                }
            }
        }
    }

    /// "Ryanair (service@ryanair.com)" reads as "Ryanair".
    private static func sender(_ from: String) -> String {
        let name = from.replacingOccurrences(of: #"\s*[(<].*[)>]\s*$"#, with: "", options: .regularExpression)
        return name.isEmpty ? from : name
    }
}

// MARK: - Draft card

/// A message Claude wrote for the user to send. The text is editable in place;
/// Send posts a normal chat message ("Send it.", with the edited text if it changed)
/// and the card then follows that turn: sending, sent, or not sent.
private struct DraftCard: View {
    let draft: ChatQuote
    let id: String
    @EnvironmentObject private var claudeCodeService: ClaudeCodeService
    @State private var text: String
    @FocusState private var isEditing: Bool

    init(draft: ChatQuote, id: String) {
        self.draft = draft
        self.id = id
        _text = State(initialValue: draft.messages.first?.text ?? "")
    }

    private var message: ChatQuote.Message? { draft.messages.first }
    private var sent: (text: String, activityID: UUID)? { claudeCodeService.sentDrafts[id] }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                BrandGlyph(id: draft.source, size: 12)
                if sent == nil {
                    Text("Draft")
                        .font(OrtusTheme.Typo.badge)
                        .foregroundStyle(OrtusTheme.accentInk)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(OrtusTheme.accentSoft))
                }
                Text(Self.appName(draft.source)).foregroundStyle(OrtusTheme.textMuted)
            }
            .font(OrtusTheme.Typo.caption)

            if draft.source == "gmail", !draft.place.isEmpty {
                Text(draft.place).font(OrtusTheme.Typo.bodyMedium.weight(.semibold))
            }
            if let recipient = message?.to ?? (draft.source == "gmail" ? nil : draft.place) {
                Text("To \(recipient)").font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
            }

            if let sent {
                Text(sent.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Divider()
                status(sent.activityID)
            } else {
                editor
                Button("Send") { claudeCodeService.sendDraft(id: id, original: message?.text ?? "", edited: text) }
                    .buttonStyle(OrtusPrimaryButtonStyle())
                    .disabled(claudeCodeService.isProcessing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(OrtusTheme.cardSurface))
        .overlay(shape.strokeBorder(OrtusTheme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    /// A recessed field that grows with the text: the hidden copy sets the height.
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            Text(text + " ").padding(.horizontal, 5).opacity(0).accessibilityHidden(true)
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($isEditing)
        }
        .font(OrtusTheme.Typo.body)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusSM, style: .continuous).fill(OrtusTheme.inputSurface))
        .overlay(
            RoundedRectangle(cornerRadius: OrtusTheme.radiusSM, style: .continuous)
                .strokeBorder(isEditing ? OrtusTheme.accent.opacity(0.55) : OrtusTheme.hairline, lineWidth: 1)
        )
    }

    /// Only claims "Sent" once the turn finished and a send step in this app succeeded.
    /// A false "Not sent" is better than a false "Sent"; Claude's reply says what happened.
    @ViewBuilder private func status(_ activityID: UUID) -> some View {
        let activity = claudeCodeService.messages.first { $0.id == activityID }.flatMap { message -> ChatActivity? in
            if case .activity(let activity) = message.kind { activity } else { nil }
        }
        if let activity, let finished = activity.finishedAt {
            let succeeded = !activity.wasStopped && activity.toolSteps.contains {
                $0.status == .done && $0.verb == "Sent" && ($0.source?.rawValue == draft.source || ChatActivity.Source(rawValue: draft.source) == nil)
            }
            if succeeded {
                Label("Sent at \(finished.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark")
                    .foregroundStyle(OrtusTheme.success)
            } else {
                Label("Not sent. See the reply below.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(OrtusTheme.warning)
            }
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Sending…").foregroundStyle(OrtusTheme.textMuted)
            }
        }
    }

    private static func appName(_ source: String) -> String {
        ["gmail": "Gmail", "slack": "Slack", "linkedin": "LinkedIn", "x": "X"][source] ?? source.capitalized
    }
}

/// Opens more of a card in place. A small capsule with a chevron, so it reads as a
/// control rather than coloured text; the pointer turns into a hand over it.
private struct ExpandButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { action() }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(OrtusTheme.Typo.caption.weight(.semibold))
            .foregroundStyle(OrtusTheme.accentInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(OrtusTheme.accentSoft.opacity(isHovering ? 1 : 0.6)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}
