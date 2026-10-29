import Foundation
import OrtusCore

/// Streams below copy the shapes of real Claude Code 2.1 `stream-json` runs (with
/// made-up content): ToolSearch first, parallel calls whose results arrive out of
/// order, empty thinking blocks, a live permission refusal, a large result read back
/// with Bash.
struct ChatTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func turn(_ events: [(Double, String)]) -> ChatTurn {
        var turn = ChatTurn(startedAt: start)
        for (seconds, line) in events { turn.consume(line, at: start.addingTimeInterval(seconds)) }
        return turn
    }
    private func toolUse(_ id: String, _ name: String, _ input: String = "{}", parent: String? = nil) -> String {
        #"{"type":"assistant","parent_tool_use_id":\#(parent.map { "\"\($0)\"" } ?? "null"),"message":{"content":[{"type":"tool_use","id":"\#(id)","name":"\#(name)","input":\#(input)}]}}"#
    }
    private func result(_ id: String, error: Bool = false) -> String {
        #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"\#(id)","is_error":\#(error),"content":"…"}]}}"#
    }
    private func text(_ value: String) -> String {
        #"{"type":"assistant","message":{"content":[{"type":"text","text":"\#(value)"}]}}"#
    }
    private let thinkingTokens = #"{"type":"system","subtype":"thinking_tokens","estimated_tokens":50}"#
    private let thinking = #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":"abc"}]}}"#
    private func end(denials: String = "[]") -> String {
        #"{"type":"result","subtype":"success","is_error":false,"result":"done","permission_denials":\#(denials)}"#
    }

    func hidesPlumbingAndNamesSteps() {
        var live = ChatTurn(startedAt: start)
        live.consume(#"{"type":"system","subtype":"init"}"#, at: start)
        expect(live.didStartSession && live.activity.progress == "Thinking")
        live.consume(toolUse("t0", "ToolSearch", #"{"query":"select:mcp__claude_ai_Slack__slack_search_users"}"#), at: start)
        expect(live.activity.steps.isEmpty && live.activity.progress == "Opening Slack")
        live.consume(toolUse("t1", "mcp__claude_ai_Slack__slack_search_public_and_private", #"{"natural_language_query":"message from Maya","filters":"from:maya"}"#), at: start)
        expect(live.activity.progress == "Searching Slack")
        live.consume(result("t1"), at: start)
        expect(live.activity.progress == "Reading what it found")

        let done = turn([
            (0, toolUse("t0", "ToolSearch", #"{"query":"slack"}"#)), (1, result("t0")),
            (2, toolUse("t1", "mcp__claude_ai_Slack__slack_search_users", #"{"keywords":["Maya"]}"#)), (3, result("t1")),
            (3, toolUse("t2", "mcp__claude_ai_Slack__slack_read_thread", #"{"channel_id":"C1"}"#)), (4, result("t2")),
            (5, text("Maya asked to ship Thursday.")), (5, end()),
        ])
        expect(done.isFinished && done.answer == "Maya asked to ship Thursday.")
        expect(done.activity.toolSteps.map(\.title) == ["Looked up “Maya”", "Read the thread"])
        expect(done.activity.summary == "Searched Slack · 2 steps")
    }

    func parallelCallsKeepOneLabelAndMatchResultsByID() {
        var live = ChatTurn(startedAt: start)
        live.consume(toolUse("a", "mcp__claude_ai_Slack__slack_search_users", #"{"query":"Tom"}"#), at: start)
        live.consume(toolUse("b", "mcp__claude_ai_Gmail__search_threads", #"{"query":"from:tom"}"#), at: start)
        expect(live.activity.progress == "Searching Slack and Gmail")
        live.consume(result("b"), at: start) // Gmail answers first
        expect(live.activity.progress == "Looking up “Tom”")
        live.consume(result("a"), at: start)
        live.consume(end(), at: start)
        expect(live.activity.toolSteps.allSatisfy { $0.status == .done })
        expect(live.activity.summary == "Searched Slack and Gmail · 2 steps")
    }

    func thinkingNarrationAndHelpersFoldIntoSteps() {
        let done = turn([
            (0, text("Let me check your calendar.")),
            (1, toolUse("c", "mcp__claude_ai_Google_Calendar__list_events")),
            (1, toolUse("x", "mcp__claude_ai_Slack__slack_search_public", parent: "agent-1")), // inside a helper agent
            (2, result("c")),
            (3, thinkingTokens), (6, thinkingTokens), (8, thinking),
            (8, text("Two meetings left today.")), (8, end()),
        ])
        expect(done.answer == "Two meetings left today.")
        expect(done.activity.steps.map(\.kind) == [.note, .tool, .thought])
        expect(done.activity.steps[2].title == "Thought for 5s")
        expect(done.activity.summary == "Checked your calendar · 1 step")
        // A thinking block with no token events before it adds nothing.
        expect(turn([(0, thinking), (0, text("Hi")), (0, end())]).activity.steps.isEmpty)
    }

    func refusalsOfferAllowOnlyForConnectors() {
        let savedResult = #"{"command":"jq -r .body /Users/me/.claude/projects/x/tool-results/mcp-gmail.txt"}"#
        let done = turn([
            (0, toolUse("m", "mcp__claude_ai_Gmail__get_message", #"{"messageId":"1"}"#)), (1, result("m")),
            (1, toolUse("b", "Bash", savedResult)),
            (1, #"{"type":"system","subtype":"permission_denied","tool_name":"Bash","tool_use_id":"b"}"#),
            (2, toolUse("l", "mcp__claude_ai_Slack__slack_list_user_channels")),
            (2, #"{"type":"system","subtype":"permission_denied","tool_name":"mcp__claude_ai_Slack__slack_list_user_channels","tool_use_id":"l"}"#),
            (2, result("l", error: true)),
            (3, text("I need your OK to list channels.")),
            (3, end(denials: #"[{"tool_name":"Bash"},{"tool_name":"mcp__claude_ai_Slack__slack_list_user_channels"},{"tool_name":"mcp__claude_ai_Slack__slack_list_user_channels"}]"#)),
        ])
        expect(done.deniedTools == ["mcp__claude_ai_Slack__slack_list_user_channels"])
        expect(done.activity.toolSteps.map(\.title) == ["Opened the email", "Listed your channels"])
        expect(done.activity.toolSteps.last?.status == .needsPermission)
        expect(!done.activity.hasProblem)

        let failed = turn([(0, toolUse("w", "WebSearch", #"{"query":"ortus"}"#)), (1, result("w", error: true)),
                           (2, #"{"type":"result","is_error":true,"result":"Overloaded"}"#)])
        expect(failed.activity.hasProblem && failed.failure == "Overloaded")
        expect(failed.activity.toolSteps.first?.title == "Searched the web “ortus”")

        var stopped = turn([(0, toolUse("s", "mcp__claude_ai_Slack__slack_search_public", #"{"query":"q"}"#))])
        stopped.finish(at: start.addingTimeInterval(4), stopped: true)
        expect(stopped.isFinished && stopped.activity.wasStopped)
    }

    func parsesAnswersIntoBlocksAndQuoteCards() {
        let answer = """
        Maya asked to **ship Thursday**.

        ```quote
        source: slack
        place: #launch
        ---
        from: Maya Chen
        time: 2026-10-25T10:12:00+00:00

        Can we ship Thursday?
        Friday is tight.
        ---
        skipped: 3
        ---
        from: Tom Price
        time: 2026-10-25T10:40+01:00

        Fine by me
        ```

        - one
        - two
        1. first
        > quoted
        ## Heading
        ```quote
        not a card
        ```
        """
        let blocks = ChatMarkdown.blocks(answer)
        expect(blocks.count == 7)
        expect(blocks[0] == .paragraph("Maya asked to **ship Thursday**."))
        guard case .quote(let quote) = blocks[1] else { return expect(false) }
        expect(quote.source == "slack" && quote.place == "#launch" && quote.entries.count == 3)
        expect(quote.messages.map(\.from) == ["Maya Chen", "Tom Price"])
        expect(quote.messages[0].text == "Can we ship Thursday?\nFriday is tight.")
        expect(quote.messages[0].time == ISO8601DateFormatter().date(from: "2026-10-25T10:12:00Z"))
        expect(quote.messages[1].time == ISO8601DateFormatter().date(from: "2026-10-25T09:40:00Z"))
        expect(quote.entries[1] == .skipped(3))
        expect(blocks[2] == .bullets(["one", "two"]) && blocks[3] == .numbered(["first"]))
        expect(blocks[4] == .blockquote("quoted") && blocks[5] == .paragraph("**Heading**"))
        expect(blocks[6] == .blockquote("not a card")) // a quote fence without messages stays readable
    }

    func labelsTimesRelativeToNow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        let now = ISO8601DateFormatter().date(from: "2026-10-26T13:00:00Z")!
        let label = { (iso: String) in ChatQuote.timeLabel(ISO8601DateFormatter().date(from: iso)!, now: now, calendar: calendar) }
        expect(label("2026-10-26T09:37:00Z").contains(":") && !label("2026-10-26T09:37:00Z").hasPrefix("Yesterday")) // today: time only
        expect(label("2026-10-25T09:37:00Z").hasPrefix("Yesterday "))
        expect(label("2026-10-23T09:37:00Z").contains(":") && !label("2026-10-23T09:37:00Z").hasPrefix("Yesterday")) // weekday + time
        expect(!label("2026-10-01T09:37:00Z").contains(":")) // older: date only
    }
}
