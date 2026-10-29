import Foundation

/// One chat answer rebuilt from Claude Code's `--output-format stream-json` events:
/// what Claude did on the way (the activity) and the text it ends with (the answer).
///
/// Built from recorded runs. Claude Code also sends plumbing that should never look
/// like work: `ToolSearch` loading tool definitions, reads of results it saved to disk
/// because they were too large, and thinking blocks whose text is always empty.
public struct ChatTurn: Equatable, Sendable {
    public private(set) var activity: ChatActivity
    /// Text written after the last tool call. Text written before a tool call is
    /// narration ("Let me check Slack") and moves into the activity instead.
    public private(set) var answer = ""
    /// Tools Claude was refused and the user can allow: connectors and web tools only.
    /// Built-in tools like Bash are Claude Code's own business, never an Allow button.
    public private(set) var deniedTools: [String] = []
    public private(set) var failure: String?
    public private(set) var didStartSession = false
    public var isFinished: Bool { activity.finishedAt != nil }

    private var pendingText: [String] = []
    private var thinkingSince: Date?

    public init(startedAt: Date) {
        activity = ChatActivity(startedAt: startedAt)
    }

    public mutating func consume(_ line: String, at now: Date) {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }
        // Events from inside a helper agent: its own tool calls are not ours to show.
        if event["parent_tool_use_id"] is String { return }

        switch (type, event["subtype"] as? String) {
        case ("system", "init"):
            didStartSession = true
        case ("system", "thinking_tokens"):
            if thinkingSince == nil { thinkingSince = now }
        case ("system", "permission_denied"):
            if let id = event["tool_use_id"] as? String { activity.setStatus(.needsPermission, forStep: id) }
        case ("assistant", _):
            let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            for block in content { consumeAssistant(block, at: now) }
        case ("user", _):
            let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            for block in content where block["type"] as? String == "tool_result" {
                guard let id = block["tool_use_id"] as? String else { continue }
                activity.complete(step: id, failed: block["is_error"] as? Bool == true)
            }
        case ("result", _):
            if event["is_error"] as? Bool == true {
                failure = (event["result"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Claude Code stopped with an error."
            }
            for denial in event["permission_denials"] as? [[String: Any]] ?? [] {
                guard let name = denial["tool_name"] as? String, Self.isAllowable(name), !deniedTools.contains(name) else { continue }
                deniedTools.append(name)
            }
            finish(at: now)
        default:
            break
        }
    }

    /// The process ended, or the user stopped it, before a result arrived.
    public mutating func finish(at now: Date, stopped: Bool = false) {
        guard !isFinished else { return }
        activity.finish(at: now, stopped: stopped)
    }

    private mutating func consumeAssistant(_ block: [String: Any], at now: Date) {
        switch block["type"] as? String {
        case "text":
            guard let text = block["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            pendingText.append(text)
            answer = pendingText.joined(separator: "\n\n")
        case "thinking":
            // The thinking text itself is empty; only its duration is worth showing.
            if let since = thinkingSince { activity.addThought(seconds: max(1, Int(now.timeIntervalSince(since).rounded()))) }
            thinkingSince = nil
        case "tool_use":
            if !pendingText.isEmpty {
                activity.addNote(pendingText.joined(separator: " "))
                pendingText = []
                answer = ""
            }
            guard let id = block["id"] as? String, let name = block["name"] as? String else { return }
            activity.startTool(id: id, name: name, input: block["input"] as? [String: Any] ?? [:])
        default:
            break
        }
    }

    static func isAllowable(_ tool: String) -> Bool {
        tool.hasPrefix("mcp__") || tool == "WebSearch" || tool == "WebFetch"
    }
}

/// The work behind one answer, shown as a single collapsible line in the chat.
public struct ChatActivity: Equatable, Sendable {
    public enum Source: String, Equatable, Sendable {
        case slack, gmail, calendar, drive, notion, web

        var name: String {
            switch self {
            case .slack: "Slack"
            case .gmail: "Gmail"
            case .calendar: "your calendar"
            case .drive: "Drive"
            case .notion: "Notion"
            case .web: "the web"
            }
        }
    }

    public struct Step: Equatable, Sendable, Identifiable {
        public enum Kind: Equatable, Sendable { case tool, thought, note }
        public enum Status: Equatable, Sendable { case running, done, failed, needsPermission }
        public let id: String
        public let kind: Kind
        public let source: Source?
        /// Past tense, for the list of steps: "Searched Slack “haroun”".
        public let title: String
        /// Present tense, for the live line: "Searching Slack".
        public let progress: String
        public var status: Status
        let isSearch: Bool
    }

    public let startedAt: Date
    public private(set) var finishedAt: Date?
    public private(set) var wasStopped = false
    public private(set) var steps: [Step] = []
    /// The connector `ToolSearch` was loading, so the live line can say where Claude
    /// is about to look before the first real call.
    private var upcomingSource: Source?

    public init(startedAt: Date) { self.startedAt = startedAt }

    public var toolSteps: [Step] { steps.filter { $0.kind == .tool } }
    public var hasProblem: Bool { toolSteps.contains { $0.status == .failed } }

    /// "Searched Slack and Gmail · 3 steps", or nil when Claude used no tools.
    public var summary: String? {
        let tools = toolSteps
        guard !tools.isEmpty else { return nil }
        var sources: [Source] = []
        for source in tools.compactMap(\.source) where !sources.contains(source) { sources.append(source) }
        let verb = tools.contains(where: \.isSearch) ? "Searched" : "Checked"
        let what = sources.isEmpty ? "Worked on it" : "\(verb) \(Self.list(sources.map(\.name)))"
        return "\(what) · \(tools.count) step\(tools.count == 1 ? "" : "s")"
    }

    /// What the live line says while Claude works, without the trailing ellipsis.
    public var progress: String {
        let running = toolSteps.filter { $0.status == .running }
        var runningSources: [Source] = []
        for source in running.compactMap(\.source) where !runningSources.contains(source) { runningSources.append(source) }
        // Parallel calls in different apps: one stable label instead of flicker.
        if runningSources.count > 1 { return "Searching \(Self.list(runningSources.map(\.name)))" }
        if let first = running.first { return first.progress }
        if !toolSteps.isEmpty { return "Reading what it found" }
        if let upcomingSource { return "Opening \(upcomingSource.name)" }
        return "Thinking"
    }

    mutating func startTool(id: String, name: String, input: [String: Any]) {
        if name == "ToolSearch" {
            upcomingSource = Self.source(in: (input["query"] as? String) ?? "") ?? upcomingSource
            return
        }
        guard let step = Self.describe(id: id, name: name, input: input) else { return }
        steps.append(step)
    }

    mutating func complete(step id: String, failed: Bool) {
        guard let index = steps.firstIndex(where: { $0.id == id }), steps[index].status == .running else { return }
        steps[index].status = failed ? .failed : .done
    }

    mutating func setStatus(_ status: Step.Status, forStep id: String) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].status = status
    }

    mutating func addThought(seconds: Int) {
        steps.append(Step(id: "thought-\(steps.count)", kind: .thought, source: nil, title: "Thought for \(seconds)s", progress: "Thinking", status: .done, isSearch: false))
    }

    mutating func addNote(_ text: String) {
        steps.append(Step(id: "note-\(steps.count)", kind: .note, source: nil, title: text, progress: "Thinking", status: .done, isSearch: false))
    }

    mutating func finish(at date: Date, stopped: Bool) {
        finishedAt = date
        wasStopped = stopped
    }

    // MARK: - Naming tools

    /// Plain-language names for a tool call, or nil for plumbing that isn't shown.
    static func describe(id: String, name: String, input: [String: Any]) -> Step? {
        func step(_ source: Source?, _ title: String, _ progress: String, search: Bool = false) -> Step {
            Step(id: id, kind: .tool, source: source, title: title, progress: progress, status: .running, isSearch: search)
        }
        let query = Self.query(in: input).map { " “\($0)”" } ?? ""

        switch name {
        case "ToolSearch", "TodoWrite":
            return nil
        case "Bash", "Read", "Grep", "Glob":
            // Claude Code reading a large result it saved to disk.
            if "\(input)".contains("tool-results") { return nil }
            return step(nil, "Ran a command", "Running a command")
        case "WebSearch":
            return step(.web, "Searched the web\(query)", "Searching the web", search: true)
        case "WebFetch":
            let host = (input["url"] as? String).flatMap { URL(string: $0)?.host } ?? "a page"
            return step(.web, "Opened \(host)", "Opening \(host)")
        case "Agent", "Task":
            return step(nil, "Asked a helper agent", "Asking a helper agent")
        default:
            break
        }

        guard name.hasPrefix("mcp__") else { return step(nil, "Used \(name)", "Using \(name)") }
        let parts = name.dropFirst(5).components(separatedBy: "__")
        let server = parts.first.map { $0.replacingOccurrences(of: "claude_ai_", with: "").replacingOccurrences(of: "plugin_", with: "").replacingOccurrences(of: "_", with: " ") } ?? ""
        let tool = (parts.count > 1 ? parts[1] : "").replacingOccurrences(of: "slack_", with: "")
        let source = Self.source(in: server)
        let app = source?.name ?? server

        let table: [(match: String, title: String, progress: String, search: Bool)] = [
            ("search_users", "Looked up\(query)", "Looking up\(query)", true),
            ("search_channels", "Found the channel", "Finding the channel", true),
            ("search", "Searched \(app)\(query)", "Searching \(app)", true),
            ("read_thread", "Read the thread", "Reading the thread", false),
            ("read_channel", "Read the channel", "Reading the channel", false),
            ("user_profile", "Read a profile", "Reading a profile", false),
            ("list_user_channels", "Listed your channels", "Listing your channels", false),
            ("get_thread", "Opened the email", "Opening the email", false),
            ("get_message", "Opened the email", "Opening the email", false),
            ("list_events", "Checked your calendar", "Checking your calendar", false),
            ("get_event", "Checked your calendar", "Checking your calendar", false),
            ("suggest_time", "Checked your calendar", "Checking your calendar", false),
            ("read_file", "Opened a document", "Opening a document", false),
            ("fetch", "Opened a page", "Opening a page", false),
        ]
        if let row = table.first(where: { tool.contains($0.match) }) {
            return step(source, row.title, row.progress, search: row.search)
        }
        let words = tool.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return step(source, "Used \(app): \(words)", "Using \(app)")
    }

    /// The most readable search text in a tool's input, shortened for one line.
    static func query(in input: [String: Any]) -> String? {
        let keywords = (input["keywords"] as? [String])?.joined(separator: " ")
        let candidates = [input["natural_language_query"] as? String, input["query"] as? String, keywords]
        guard var text = candidates.compactMap({ $0?.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) else { return nil }
        // Slack user mentions are IDs, not names.
        text = text.replacingOccurrences(of: #"<@\w+>"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return text.count > 36 ? String(text.prefix(36)) + "…" : text
    }

    static func source(in text: String) -> Source? {
        let lower = text.lowercased()
        if lower.contains("slack") { return .slack }
        if lower.contains("gmail") { return .gmail }
        if lower.contains("calendar") { return .calendar }
        if lower.contains("drive") || lower.contains("docs") || lower.contains("sheets") || lower.contains("slides") { return .drive }
        if lower.contains("notion") { return .notion }
        return nil
    }

    static func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }
}
