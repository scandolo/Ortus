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
            ForEach(Array(Self.segments(ChatMarkdown.blocks(text)).enumerated()), id: \.offset) { _, segment in
                if ProseText.draws(segment.blocks[0]) {
                    ProseText(blocks: segment.blocks)
                } else {
                    blockView(segment.blocks[0], id: "\(messageID)-\(segment.index)")
                }
            }
        }
        .font(OrtusTheme.Typo.body)
        .textSelection(.enabled)
        .tint(OrtusTheme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    /// Runs of paragraphs and lists become one segment, so a selection can cross them;
    /// every other block is a segment of its own. `index` is the first block's position,
    /// which a draft card's id is built from.
    private static func segments(_ blocks: [ChatBlock]) -> [(index: Int, blocks: [ChatBlock])] {
        var segments: [(index: Int, blocks: [ChatBlock])] = []
        for (index, block) in blocks.enumerated() {
            if ProseText.draws(block), let last = segments.last?.blocks.last, ProseText.draws(last) {
                segments[segments.count - 1].blocks.append(block)
            } else {
                segments.append((index, [block]))
            }
        }
        return segments
    }

    @ViewBuilder private func blockView(_ block: ChatBlock, id: String) -> some View {
        switch block {
        case .paragraph, .bullets, .numbered:
            ProseText(blocks: [block])
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(OrtusTheme.text).frame(width: 2)
                Text(Self.inline(text)).lineSpacing(4)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let text):
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous).fill(OrtusTheme.fill))
        case .quote(let quote):
            QuoteCard(quote: quote)
        case .draft(let draft):
            DraftCard(draft: draft, id: id)
        case .verification(let code):
            VerificationCodeCard(code: code)
        }
    }

    /// Links are underlined, so they read as links in the text colour (quotes, cards).
    static func inline(_ text: String) -> AttributedString {
        var parsed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        for range in parsed.runs.filter({ $0.link != nil }).map(\.range) {
            parsed[range].underlineStyle = .single
        }
        return parsed
    }
}

// MARK: - Prose

/// Paragraphs and lists in a row, drawn by one AppKit text view so a selection can run
/// across them: SwiftUI only selects within a single Text. Styled like the SwiftUI
/// layout it replaced: 8pt between blocks, 3pt between list items, a muted marker and
/// wrapped lines that line up with the item's text.
private struct ProseText: NSViewRepresentable {
    let blocks: [ChatBlock]

    static func draws(_ block: ChatBlock) -> Bool {
        switch block {
        case .paragraph, .bullets, .numbered: true
        default: false
        }
    }

    final class Coordinator {
        var blocks: [ChatBlock] = []
        var scale: CGFloat = 0
        /// Lays out the same text at the width SwiftUI asks about, without touching the
        /// view on screen.
        let measure = NSLayoutManager()
        let container = NSTextContainer()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        // SwiftUI sets the frame; the view never resizes itself.
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.linkTextAttributes = [.foregroundColor: NSColor(OrtusTheme.text), .underlineStyle: NSUnderlineStyle.single.rawValue,
                                   .cursor: NSCursor.pointingHand]

        let coordinator = context.coordinator
        coordinator.container.lineFragmentPadding = 0
        coordinator.measure.addTextContainer(coordinator.container)
        view.textStorage?.addLayoutManager(coordinator.measure)
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        // Only when the text changed, so a selection survives other updates.
        let scale = context.environment.displayScale
        // Bone or ink like the panel, not the system appearance.
        view.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        guard context.coordinator.blocks != blocks || context.coordinator.scale != scale else { return }
        context.coordinator.blocks = blocks
        context.coordinator.scale = scale
        view.textStorage?.setAttributedString(Self.text(blocks, scale: scale))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let coordinator = context.coordinator
        coordinator.container.size = NSSize(width: width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        coordinator.measure.ensureLayout(for: coordinator.container)
        let used = coordinator.measure.usedRect(for: coordinator.container)
        return CGSize(width: width ?? ceil(used.width), height: ceil(used.height))
    }

    /// `scale` is the display's: SwiftUI rounds a marker's width up to whole pixels, so
    /// the item's text starts there.
    static func text(_ blocks: [ChatBlock], scale: CGFloat) -> NSAttributedString {
        let font = OrtusFont.nsText(15)
        // Tabular digits, so "1." to "9." line up.
        let markerFont: NSFont = {
            let base = OrtusFont.nsText(15)
            let tabular = base.fontDescriptor.addingAttributes([.featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]]])
            return NSFont(descriptor: tabular, size: 15) ?? base
        }()
        let text = NSMutableAttributedString()
        for (blockIndex, block) in blocks.enumerated() {
            let rows: [(marker: String?, text: String)]
            switch block {
            case .paragraph(let paragraph): rows = [(nil, paragraph)]
            case .bullets(let items): rows = items.map { ("•", $0) }
            case .numbered(let items): rows = items.enumerated().map { ("\($0.offset + 1).", $0.element) }
            default: rows = []
            }
            for (rowIndex, row) in rows.enumerated() {
                let start = text.length
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 4
                if rowIndex < rows.count - 1 {
                    style.paragraphSpacing = 4
                } else if blockIndex < blocks.count - 1 {
                    style.paragraphSpacing = 10
                }
                if let marker = row.marker {
                    let width = (marker as NSString).size(withAttributes: [.font: markerFont]).width
                    let indent = 2 + ceil(width * scale) / scale + 6
                    style.firstLineHeadIndent = 2
                    style.headIndent = indent
                    style.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
                    text.append(NSAttributedString(string: marker + "\t", attributes: [
                        .font: markerFont, .foregroundColor: NSColor(OrtusTheme.textMuted),
                    ]))
                }
                text.append(inline(row.text, font: font))
                if rowIndex < rows.count - 1 || blockIndex < blocks.count - 1 {
                    text.append(NSAttributedString(string: "\n", attributes: [.font: font]))
                }
                text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: text.length - start))
            }
        }
        return text
    }

    /// Bold, italic, code, strikethrough and links from the inline markdown.
    private static func inline(_ markdown: String, font: NSFont) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let parsed = ChatAnswerView.inline(markdown)
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            // Archivo has no italic: emphasis leans the roman instead.
            var runFont = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize: font.pointSize - 2, weight: .regular) : font
            if intent.contains(.stronglyEmphasized) && !intent.contains(.code) { runFont = OrtusFont.nsText(font.pointSize, .bold) }
            var attributes: [NSAttributedString.Key: Any] = [.font: runFont, .foregroundColor: NSColor(OrtusTheme.text)]
            if intent.contains(.emphasized) { attributes[.obliqueness] = 0.18 }
            if run.link != nil { attributes[.font] = OrtusFont.nsText(font.pointSize, .bold) }
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            // A line break inside a paragraph, not a new paragraph with its spacing.
            let string = String(parsed[run.range].characters).replacingOccurrences(of: "\n", with: "\u{2028}")
            text.append(NSAttributedString(string: string, attributes: attributes))
        }
        return text
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
        VStack(alignment: .leading, spacing: 10) {
            header
            if quote.source == "gmail" { email } else { thread }
        }
        .chatCard()
    }

    private var header: some View {
        HStack(spacing: 7) {
            BrandGlyph(id: quote.source, size: 13, color: OrtusTheme.textMuted)
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
        ["gmail", "linkedin"].contains(quote.source) || quote.place.isEmpty ? appName(quote.source) : quote.place
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
                .padding(.leading, 36)
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
                .font(OrtusTheme.Typo.caption)
                .foregroundStyle(OrtusTheme.textMuted)
                .padding(.leading, 36)
        case .message(let message):
            HStack(alignment: .top, spacing: 10) {
                avatar(message.from)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(message.from).font(OrtusFont.text(14, .bold))
                        if let time = message.time {
                            Text(ChatQuote.timeLabel(time, now: Date()))
                                .font(OrtusTheme.Typo.meta)
                                .foregroundStyle(OrtusTheme.textMuted)
                        }
                    }
                    if let about = message.about {
                        Text(about).font(OrtusTheme.Typo.meta).foregroundStyle(OrtusTheme.textMuted)
                    }
                    Text(ChatAnswerView.inline(message.text)).font(OrtusFont.text(14)).lineSpacing(3)
                }
            }
        }
    }

    private func avatar(_ name: String) -> some View {
        Text(name.first.map { String($0).uppercased() } ?? "?")
            .font(OrtusTheme.Typo.badge)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(OrtusTheme.cardChip))
    }

    // MARK: Email

    @ViewBuilder private var email: some View {
        let messages = quote.messages
        VStack(alignment: .leading, spacing: 6) {
            if !quote.place.isEmpty {
                Text(quote.place).font(OrtusFont.text(15, .bold))
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
                    .font(OrtusFont.text(14))
                    .lineSpacing(3)
                    .lineLimit(showsFullEmail ? nil : 3)
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

/// The app a card's `source` names, for its header.
private func appName(_ source: String) -> String {
    ["gmail": "Gmail", "slack": "Slack", "linkedin": "LinkedIn", "x": "X"][source] ?? source.capitalized
}

private extension View {
    /// The lifted card the quote and draft cards sit on, like OrtusGroup.
    func chatCard() -> some View {
        environment(\.ortusOnCard, true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous).fill(OrtusTheme.cardSurface))
    }

    /// The primary button for a card's one action.
    func draftButton(size: OrtusButtonSize = .small) -> some View {
        buttonStyle(OrtusPrimaryButtonStyle(size: size))
    }
}

// MARK: - Draft card

/// A message Claude wrote for the user to send. The text reads like the rest of the
/// card and is editable in place. Send posts a normal chat message ("Send it.", with
/// the edited text if it changed); the card then keeps what was sent, read-only, and
/// the activity line and Claude's reply below say how it went. An "email" draft is one
/// Claude can't send (no email connected): it gets Copy instead of Send.
private struct DraftCard: View {
    let draft: ChatQuote
    let id: String
    @EnvironmentObject private var claudeCodeService: ClaudeCodeService
    @State private var text: String
    @State private var isHovering = false
    @State private var copied = false
    @FocusState private var isEditing: Bool

    init(draft: ChatQuote, id: String) {
        self.draft = draft
        self.id = id
        _text = State(initialValue: draft.messages.first?.text ?? "")
    }

    private var message: ChatQuote.Message? { draft.messages.first }
    private var isEmail: Bool { draft.source == "gmail" || draft.source == "email" }

    var body: some View {
        let sent = claudeCodeService.sentDrafts[id]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if draft.source == "email" {
                    OrtusIcon(.mail, size: 14)
                } else {
                    BrandGlyph(id: draft.source, size: 14)
                }
                if sent == nil {
                    Text("DRAFT")
                        .font(OrtusFont.text(11, .extraBold)).tracking(1.2)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(OrtusTheme.cardChip))
                }
                Text(appName(draft.source)).foregroundStyle(OrtusTheme.textMuted)
                Spacer(minLength: 0)
                if sent == nil {
                    Button { isEditing = true } label: {
                        HStack(spacing: 6) {
                            OrtusIcon(.edit, size: 13)
                            Text("Edit").font(OrtusFont.text(13, .semibold))
                        }
                        .foregroundStyle(isEditing ? OrtusTheme.text : OrtusTheme.textMuted)
                    }
                    .buttonStyle(OrtusPressableStyle(inset: 4))
                    .help("Change the text before sending")
                }
            }
            .font(OrtusTheme.Typo.caption)

            if isEmail, !draft.place.isEmpty {
                Text(draft.place).font(OrtusFont.text(15, .bold))
            }
            if let recipient = message?.to ?? (isEmail ? nil : draft.place) {
                Text("To \(recipient)").font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
            }
            if let cc = message?.cc {
                Text("Cc \(cc)").font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
            }

            if let sent {
                Text(sent).font(OrtusFont.text(14)).lineSpacing(3).textSelection(.enabled)
            } else {
                editor
                Rectangle().fill(OrtusTheme.line).frame(height: 1).padding(.horizontal, -14).padding(.top, 2)
                if draft.source == "email" { copyButton } else { sendButton }
            }
        }
        .chatCard()
    }

    /// Looks like plain text; a faint tint on hover and while typing is the only chrome.
    /// The hidden copy sets the height, so the field grows with the text.
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            Text(text + " ").opacity(0).accessibilityHidden(true)
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($isEditing)
                .padding(.horizontal, -5) // NSTextView's line padding, so the text lines up with the labels
        }
        .font(OrtusFont.text(14))
        .lineSpacing(3)
        .background(
            RoundedRectangle(cornerRadius: OrtusTheme.radiusSM, style: .continuous)
                .fill(OrtusTheme.text.opacity(isEditing ? 0.06 : isHovering ? 0.03 : 0))
                .padding(-4)
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    private var sendButton: some View {
        Button("Send") { claudeCodeService.sendDraft(id: id, original: message?.text ?? "", edited: text) }
            .draftButton()
            .opacity(claudeCodeService.isProcessing ? 0.45 : 1)
            .disabled(claudeCodeService.isProcessing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Copies the text as edited; the address is in the To line and in Claude's reply.
    private var copyButton: some View {
        Button(copied ? "Copied" : "Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(2)); copied = false }
        }
        .draftButton()
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

// MARK: - Verification code card

/// A one-time code Claude found, big enough to read at a glance, with one Copy
/// button: the user is usually halfway through logging in somewhere else.
private struct VerificationCodeCard: View {
    let code: ChatCode
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if ["gmail", "slack"].contains(code.source) {
                    BrandGlyph(id: code.source, size: 14, color: OrtusTheme.textMuted)
                } else {
                    OrtusIcon(.key, size: 14)
                }
                Text(code.from.isEmpty ? "Verification code" : code.from).lineLimit(1)
                Spacer(minLength: 0)
                if let time = code.time { Text(ChatQuote.timeLabel(time, now: Date())) }
            }
            .font(OrtusTheme.Typo.caption)
            .foregroundStyle(OrtusTheme.textMuted)

            HStack(alignment: .center, spacing: OrtusTheme.spacingSM) {
                Text(code.code)
                    .font(OrtusFont.display(42))
                    .monospacedDigit()
                    .tracking(4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.code, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                } label: {
                    HStack(spacing: 8) {
                        OrtusIcon(copied ? .check : .copy, size: 15)
                        Text(copied ? "Copied" : "Copy")
                    }
                }
                .draftButton(size: .medium)
                .help("Copy the code")
            }
        }
        .chatCard()
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
            HStack(spacing: 6) {
                Text(title)
                OrtusIcon(.chevronDown, size: 10)
            }
            .font(OrtusFont.text(13, .bold))
            .foregroundStyle(OrtusTheme.text)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(OrtusTheme.cardChip.opacity(isHovering ? 0.75 : 1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}
