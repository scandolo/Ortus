import Foundation

/// A chat answer split into blocks the panel can lay out. Inline markdown (bold,
/// links, code) stays in the strings; the app renders it per block.
public enum ChatBlock: Equatable, Sendable {
    case paragraph(String)
    case bullets([String])
    case numbered([String])
    case blockquote(String)
    case code(String)
    case quote(ChatQuote)
}

/// Messages Claude quoted verbatim from Slack, email or a post, written in a
/// fenced `quote` block (format in ClaudeCodeService's system prompt):
///
///     ```quote
///     source: slack
///     place: #general
///     ---
///     from: Maya Chen
///     time: 2026-10-25T10:12:00+00:00
///
///     Can we ship Thursday?
///     ---
///     skipped: 3
///     ```
public struct ChatQuote: Equatable, Sendable {
    public struct Message: Equatable, Sendable {
        public var from = ""
        public var to: String?
        public var about: String?
        public var time: Date?
        public var text = ""
    }
    public enum Entry: Equatable, Sendable {
        case message(Message)
        /// Replies Claude left out of a thread.
        case skipped(Int)
    }

    /// slack, gmail, linkedin, x or other.
    public var source: String
    /// The channel, the email subject or the site.
    public var place: String
    public var entries: [Entry]

    public var messages: [Message] {
        entries.compactMap { if case .message(let message) = $0 { message } else { nil } }
    }

    /// Nil when the block has no message in it, so the caller can show it as text.
    static func parse(_ body: String) -> ChatQuote? {
        let sections = body.components(separatedBy: "\n").split(whereSeparator: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        guard let header = sections.first else { return nil }
        let fields = Self.fields(header)
        var entries: [Entry] = []
        for section in sections.dropFirst() {
            let lines = Array(section)
            let blank = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).isEmpty } ?? lines.count
            let head = Self.fields(lines[..<blank])
            if let skipped = head["skipped"].flatMap({ Int($0) }) {
                entries.append(.skipped(skipped))
                continue
            }
            var message = Message()
            message.from = head["from"] ?? ""
            message.to = head["to"]
            message.about = head["about"]
            message.time = head["time"].flatMap(Self.date)
            message.text = lines[blank...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.from.isEmpty || !message.text.isEmpty else { continue }
            entries.append(.message(message))
        }
        guard entries.contains(where: { if case .message = $0 { true } else { false } }) else { return nil }
        return ChatQuote(source: fields["source"]?.lowercased() ?? "other", place: fields["place"] ?? "", entries: entries)
    }

    private static func fields<S: Sequence>(_ lines: S) -> [String: String] where S.Element == String {
        var fields: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty, !key.contains(" ") else { continue }
            fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return fields
    }

    static func date(_ text: String) -> Date? {
        let full = ISO8601DateFormatter()
        if let date = full.date(from: text) { return date }
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = full.date(from: text) { return date }
        // "2026-10-25T10:37+01:00", without seconds.
        let short = DateFormatter()
        short.locale = Locale(identifier: "en_US_POSIX")
        short.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        return short.date(from: text)
    }

    /// "10:37" today, "Yesterday 10:37", "Sat 10:37" this week, otherwise "25 Oct".
    public static func timeLabel(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, calendar: calendar, timeZone: calendar.timeZone))
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case 0: return time
        case 1: return "Yesterday \(time)"
        case 2..<7: return date.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)) + " \(time)"
        default: return date.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated))
        }
    }
}

public enum ChatMarkdown {
    public static func blocks(_ text: String) -> [ChatBlock] {
        var blocks: [ChatBlock] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }

        let lines = text.components(separatedBy: "\n")
        var index = 0
        func take(while matches: (String) -> Bool) -> [String] {
            var taken: [String] = []
            while index < lines.count, matches(lines[index]) { taken.append(lines[index]); index += 1 }
            return taken
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush()
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
                index += 1
                let body = take { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }.joined(separator: "\n")
                index += 1 // closing fence
                if language == "quote" {
                    blocks.append(ChatQuote.parse(body).map(ChatBlock.quote) ?? .blockquote(body))
                } else {
                    blocks.append(.code(body))
                }
            } else if Self.bullet(line) != nil {
                flush()
                blocks.append(.bullets(take { Self.bullet($0) != nil }.compactMap(Self.bullet)))
            } else if Self.numbered(line) != nil {
                flush()
                blocks.append(.numbered(take { Self.numbered($0) != nil }.compactMap(Self.numbered)))
            } else if trimmed.hasPrefix(">") {
                flush()
                let quoted = take { $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
                blocks.append(.blockquote(quoted.map { $0.trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")))
            } else if trimmed.isEmpty {
                flush()
                index += 1
            } else if trimmed.hasPrefix("#") {
                // Headings are too loud for the panel: keep them as a bold line.
                flush()
                blocks.append(.paragraph("**\(trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))**"))
                index += 1
            } else {
                paragraph.append(line)
                index += 1
            }
        }
        flush()
        return blocks
    }

    private static func bullet(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") else { return nil }
        return String(trimmed.dropFirst(2))
    }

    private static func numbered(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.range(of: #"^\d+[.)] "#, options: .regularExpression) else { return nil }
        return String(trimmed[match.upperBound...])
    }
}
