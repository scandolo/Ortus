import Foundation
import OrtusCore

/// Made-up chat turns for the snapshot harness. Built by replaying stream-json
/// events through ChatTurn, the same path a real answer takes.
enum ChatFixtures {
    static var refusedGmailSearch: ChatActivity {
        replay([
            (0, tool("g", "mcp__claude_ai_Gmail__search_threads", #"{"query":"from:haroun newer_than:3d"}"#)),
            (0, #"{"type":"system","subtype":"permission_denied","tool_name":"mcp__claude_ai_Gmail__search_threads","tool_use_id":"g"}"#),
            (0, result("g", error: true)),
            (3, end),
        ]).activity
    }

    // MARK: - Building events

    static func replay(_ events: [(Double, String)], startedAt: Date = Date().addingTimeInterval(-30)) -> ChatTurn {
        var turn = ChatTurn(startedAt: startedAt)
        for (seconds, line) in events { turn.consume(line, at: startedAt.addingTimeInterval(seconds)) }
        return turn
    }

    static func tool(_ id: String, _ name: String, _ input: String = "{}") -> String {
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"\#(id)","name":"\#(name)","input":\#(input)}]}}"#
    }

    static func result(_ id: String, error: Bool = false) -> String {
        #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"\#(id)","is_error":\#(error)}]}}"#
    }

    static let end = #"{"type":"result","subtype":"success","is_error":false,"permission_denials":[]}"#
}
