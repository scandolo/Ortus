import Foundation

/// One chat answer rebuilt from an agent's JSON events: what it did on the way (the
/// activity) and the text it ends with (the answer). Reads Claude Code's
/// `--output-format stream-json` and Codex's `exec --json`.
///
/// Built from recorded runs. Claude Code also sends plumbing that should never look
/// like work: `ToolSearch` loading tool definitions, reads of results it saved to disk
/// because they were too large, and thinking blocks whose text is always empty.
public struct ChatTurn: Equatable, Sendable {
    public enum Format: Sendable { case claudeCode, codex }

    public private(set) var activity: ChatActivity
    /// Text written after the last tool call. Text written before a tool call is
    /// narration ("Let me check Slack") and moves into the activity instead.
    public private(set) var answer = ""
    public private(set) var failure: String?
    public private(set) var didStartSession = false
    /// The session id Codex picked, kept for `resume` on the next turn.
    public private(set) var threadID: String?
    public var isFinished: Bool { activity.finishedAt != nil }

    private let format: Format
    private var pendingText: [String] = []
    private var thinkingSince: Date?
    private var lastEventAt: Date
    private var lastError: String?

    public init(startedAt: Date, format: Format = .claudeCode) {
        activity = ChatActivity(startedAt: startedAt)
        self.format = format
        lastEventAt = startedAt
    }

    public mutating func consume(_ line: String, at now: Date) {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }
        switch format {
        case .claudeCode: consumeClaude(event, type: type, at: now)
        case .codex: consumeCodex(event, type: type, at: now)
        }
    }

    private mutating func consumeClaude(_ event: [String: Any], type: String, at now: Date) {
        // Events from inside a helper agent: its own tool calls are not ours to show.
        if event["parent_tool_use_id"] is String { return }

        switch (type, event["subtype"] as? String) {
        case ("system", "init"):
            didStartSession = true
        case ("system", "thinking_tokens"):
            if thinkingSince == nil { thinkingSince = now }
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
            addText(block["text"] as? String)
        case "thinking":
            // The thinking text itself is empty; only its duration is worth showing.
            if let since = thinkingSince { addThought(since: since, at: now) }
            thinkingSince = nil
        case "tool_use":
            startTool(id: block["id"] as? String, name: block["name"] as? String, input: block["input"] as? [String: Any] ?? [:])
        default:
            break
        }
    }

    // MARK: - Codex

    /// Codex `exec --json` lines (codex-rs/exec/src/exec_events.rs). Tools come as
    /// `item.started` then `item.completed`; messages and reasoning only as completed.
    /// Unknown types are ignored, so new events can't break a turn.
    private mutating func consumeCodex(_ event: [String: Any], type: String, at now: Date) {
        defer { lastEventAt = now }
        switch type {
        case "thread.started":
            didStartSession = true
            threadID = event["thread_id"] as? String ?? threadID
        case "item.started", "item.completed":
            guard let item = event["item"] as? [String: Any], let id = item["id"] as? String else { return }
            consumeCodexItem(item, id: id, completed: type == "item.completed", at: now)
        case "turn.completed":
            finish(at: now)
        case "turn.failed":
            let message = ((event["error"] as? [String: Any])?["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            failure = message ?? lastError ?? "Codex stopped with an error."
            finish(at: now)
        case "error":
            lastError = (event["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? lastError
        default:
            break
        }
    }

    private mutating func consumeCodexItem(_ item: [String: Any], id: String, completed: Bool, at now: Date) {
        let failed = item["status"] as? String == "failed"
        switch item["type"] as? String {
        case "agent_message":
            if completed { addText(item["text"] as? String) }
        case "reasoning":
            guard completed else { thinkingSince = now; return }
            addThought(since: thinkingSince ?? lastEventAt, at: now)
            thinkingSince = nil
        case "command_execution":
            let exitCode = item["exit_code"] as? Int ?? 0
            codexTool(id, "Bash", ["command": item["command"] as? String ?? ""], completed: completed, failed: failed || exitCode != 0)
        case "mcp_tool_call":
            let server = item["server"] as? String ?? "", tool = item["tool"] as? String ?? ""
            // ChatGPT's connected apps all come from one server: the tool name says which app.
            let name = "mcp__\(server == "codex_apps" ? tool : server)__\(tool)"
            let hasError = item["error"].map { !($0 is NSNull) } ?? false
            codexTool(id, name, item["arguments"] as? [String: Any] ?? [:], completed: completed, failed: failed || hasError)
        case "web_search":
            codexTool(id, "WebSearch", ["query": item["query"] as? String ?? ""], completed: completed, failed: false)
        default:
            break
        }
    }

    /// The end of a tool call may be the first we hear of it. It also carries the fullest
    /// details: a web search's query arrives only then.
    private mutating func codexTool(_ id: String, _ name: String, _ input: [String: Any], completed: Bool, failed: Bool) {
        if !activity.steps.contains(where: { $0.id == id }) {
            startTool(id: id, name: name, input: input)
        } else if completed {
            activity.rename(step: id, name: name, input: input)
        }
        if completed { activity.complete(step: id, failed: failed) }
    }

    // MARK: - Shared

    private mutating func addText(_ text: String?) {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pendingText.append(text)
        answer = pendingText.joined(separator: "\n\n")
    }

    private mutating func addThought(since: Date, at now: Date) {
        activity.addThought(seconds: max(1, Int(now.timeIntervalSince(since).rounded())))
    }

    /// Text written before a tool call was narration: it moves into the activity.
    private mutating func startTool(id: String?, name: String?, input: [String: Any]) {
        if !pendingText.isEmpty {
            activity.addNote(pendingText.joined(separator: " "))
            pendingText = []
            answer = ""
        }
        guard let id, let name else { return }
        activity.startTool(id: id, name: name, input: input)
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
        public enum Status: Equatable, Sendable { case running, done, failed }
        public let id: String
        public let kind: Kind
        public let source: Source?
        /// Past tense, for the list of steps: "Searched Slack “haroun”".
        public let title: String
        /// Present tense, for the live line: "Searching Slack".
        public let progress: String
        public var status: Status
        /// How the summary describes this step: Searched, Checked or Sent.
        let verb: String
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
        let names = Self.list(Self.sources(of: tools).map(\.name))
        // A failed send didn't send anything.
        let verb = ["Sent", "Searched"].first { verb in tools.contains { $0.verb == verb && $0.status != .failed } } ?? "Checked"
        let what = names.isEmpty ? "Worked on it" : verb == "Sent" ? "Sent with \(names)" : "\(verb) \(names)"
        return "\(what) · \(tools.count) step\(tools.count == 1 ? "" : "s")"
    }

    /// What the live line says while Claude works, without the trailing ellipsis.
    public var progress: String {
        let running = toolSteps.filter { $0.status == .running }
        let runningSources = Self.sources(of: running)
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

    /// Names a step again from fuller details, keeping its status.
    mutating func rename(step id: String, name: String, input: [String: Any]) {
        guard let index = steps.firstIndex(where: { $0.id == id }), var renamed = Self.describe(id: id, name: name, input: input) else { return }
        renamed.status = steps[index].status
        steps[index] = renamed
    }

    mutating func complete(step id: String, failed: Bool) {
        guard let index = steps.firstIndex(where: { $0.id == id }), steps[index].status == .running else { return }
        steps[index].status = failed ? .failed : .done
    }

    mutating func addThought(seconds: Int) {
        steps.append(Step(id: "thought-\(steps.count)", kind: .thought, source: nil, title: "Thought for \(seconds)s", progress: "Thinking", status: .done, verb: "Checked"))
    }

    mutating func addNote(_ text: String) {
        steps.append(Step(id: "note-\(steps.count)", kind: .note, source: nil, title: text, progress: "Thinking", status: .done, verb: "Checked"))
    }

    mutating func finish(at date: Date, stopped: Bool) {
        finishedAt = date
        wasStopped = stopped
    }

    // MARK: - Naming tools

    /// Plain-language names for a tool call, or nil for plumbing that isn't shown.
    static func describe(id: String, name: String, input: [String: Any]) -> Step? {
        func step(_ source: Source?, _ title: String, _ progress: String, verb: String = "Checked") -> Step {
            Step(id: id, kind: .tool, source: source, title: title, progress: progress, status: .running, verb: verb)
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
            return step(.web, "Searched the web\(query)", "Searching the web", verb: "Searched")
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

        let table: [(match: String, title: String, progress: String, verb: String)] = [
            ("send", "Sent a message in \(app)", "Sending in \(app)", "Sent"),
            ("reply", "Replied in \(app)", "Replying in \(app)", "Sent"),
            ("post", "Posted in \(app)", "Posting in \(app)", "Sent"),
            ("search_users", "Looked up\(query)", "Looking up\(query)", "Searched"),
            ("search_channels", "Found the channel", "Finding the channel", "Searched"),
            ("search", "Searched \(app)\(query)", "Searching \(app)", "Searched"),
            ("read_thread", "Read the thread", "Reading the thread", "Checked"),
            ("read_channel", "Read the channel", "Reading the channel", "Checked"),
            ("user_profile", "Read a profile", "Reading a profile", "Checked"),
            ("list_user_channels", "Listed your channels", "Listing your channels", "Checked"),
            ("get_thread", "Opened the email", "Opening the email", "Checked"),
            ("get_message", "Opened the email", "Opening the email", "Checked"),
            ("list_events", "Checked your calendar", "Checking your calendar", "Checked"),
            ("get_event", "Checked your calendar", "Checking your calendar", "Checked"),
            ("suggest_time", "Checked your calendar", "Checking your calendar", "Checked"),
            ("read_file", "Opened a document", "Opening a document", "Checked"),
            ("fetch", "Opened a page", "Opening a page", "Checked"),
        ]
        if let row = table.first(where: { tool.contains($0.match) }) {
            return step(source, row.title, row.progress, verb: row.verb)
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

    /// The apps these steps touched, in order, once each.
    static func sources(of steps: [Step]) -> [Source] {
        var sources: [Source] = []
        for source in steps.compactMap(\.source) where !sources.contains(source) { sources.append(source) }
        return sources
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
