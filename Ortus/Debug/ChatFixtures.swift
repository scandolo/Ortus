import Foundation
import OrtusCore

/// Made-up chat turns for the snapshot harness. Built by replaying stream-json
/// events through ChatTurn, the same path a real answer takes.
enum ChatFixtures {
    /// Fills the chat for a snapshot state. False when the state isn't a chat fixture.
    @MainActor static func apply(_ state: String?, to service: ClaudeCodeService) -> Bool {
        if let state, state.hasPrefix("chat-compose") {
            applyDraft(after: String(state.dropFirst("chat-compose".count)), to: service)
            return true
        }
        guard let messages = messages(for: state) else { return false }
        service.messages = messages
        return true
    }

    /// A Slack reply drafted by Claude, and after Send: "-sent" or "-failed".
    /// "-email" is a Gmail reply instead, before Send.
    @MainActor private static func applyDraft(after phase: String, to service: ClaudeCodeService) {
        let email = phase == "-email"
        let draft = email
            ? "Hi Sara, 12 January works for us. I'll update the plan and send the PO details this week.\n\nBest,\nFederico"
            : "Thursday works for me. I'll have the pricing page ready by Wednesday evening."
        let answer = ChatMessage(role: .assistant, content: """
        Here's a reply. Send it when you're happy with it.

        ```draft
        source: \(email ? "gmail" : "slack")
        place: \(email ? "Re: Q1 pilot proposal" : "#launch")
        ---
        to: \(email ? "Sara Conti\ncc: Tom Price" : "Maya Chen, in the thread")

        \(draft)
        ```
        """)
        service.messages = [
            ChatMessage(role: .user, content: email ? "reply to sara that 12 january works" : "tell maya thursday works for me"),
            ChatMessage(role: .assistant, content: "", kind: .activity(replay([
                (0, email ? tool("t1", "mcp__claude_ai_Gmail__search_threads", #"{"query":"from:sara pilot"}"#)
                          : tool("t1", "mcp__claude_ai_Slack__slack_search_public_and_private", #"{"query":"launch Thursday"}"#)),
                (2, result("t1")), (4, end),
            ]).activity)),
            answer,
        ]
        guard !phase.isEmpty, !email else { return }
        var events = [(0.0, tool("t2", "mcp__claude_ai_Slack__slack_send_message", #"{"channel_id":"C1"}"#))]
        events += [(2, result("t2", error: phase == "-failed")), (3, end)]
        let activity = ChatMessage(role: .assistant, content: "", kind: .activity(replay(events, startedAt: Date().addingTimeInterval(-4)).activity))
        service.messages += [ChatMessage(role: .user, content: "Send it."), activity]
        if phase == "-sent" { service.messages.append(ChatMessage(role: .assistant, content: "Sent to the thread in #launch.")) }
        if phase == "-failed" { service.messages.append(ChatMessage(role: .assistant, content: "Slack didn't accept the message, so nothing was posted. Want me to try again?")) }
        service.sentDrafts["\(answer.id)-1"] = draft
    }

    /// The chat rows for a snapshot state, or nil when the state isn't a chat fixture.
    private static func messages(for state: String?) -> [ChatMessage]? {
        switch state {
        case "chat-answer", "chat-steps":
            return [
                ChatMessage(role: .user, content: "what did the team decide about the launch date?"),
                ChatMessage(role: .assistant, content: "", kind: .activity(launchThread.activity)),
                ChatMessage(role: .assistant, content: launchThread.answer),
            ]
        case "chat-prose":
            return [
                ChatMessage(role: .user, content: "Anything urgent in my email?"),
                ChatMessage(role: .assistant, content: """
                Nothing in your email needs you today. No clients, people or deadlines are waiting on a reply.

                The one thing worth a look is **Ortus CI**, which is failing:

                - The Release workflow on main failed at 12:51.
                - The Checks build on PR #53 ("Build every PR with the release toolchain") failed at 13:10.
                - Vercel preview deployments for `pr-assets` have failed five times since 12:20.

                To fix it:
                1. Open the [Release run](https://github.com/scandolo/Ortus/actions) and read the log.
                2. Rerun the *Checks* build once the release is green again.

                > The Vercel failures started before the release one.

                ```
                swift build -c release
                ```

                I haven't opened the logs, so I don't know whether these share a cause.
                The rest is notifications and newsletters.
                """),
            ]
        case "chat-email":
            return [
                ChatMessage(role: .user, content: "did sara reply about the pilot?"),
                ChatMessage(role: .assistant, content: "", kind: .activity(pilotEmail.activity)),
                ChatMessage(role: .assistant, content: pilotEmail.answer),
            ]
        case "chat-feedback", "chat-feedback-copy":
            // With Gmail connected the draft can be sent; without it, it's copied.
            let gmail = state == "chat-feedback"
            return [
                ChatMessage(role: .user, content: "the schedule i set for 9am didn't start this morning, i had to start focus by hand"),
                ChatMessage(role: .assistant, content: """
                Sorry about that. It sounds like a bug, so it's worth telling the Ortus team. \
                \(gmail ? "Here's an email you can send" : "You don't have email connected here, so copy this and send it to **support@ortusmode.com**").

                ```draft
                source: \(gmail ? "gmail" : "email")
                place: Scheduled focus didn't start at 9:00
                ---
                to: support@ortusmode.com

                Hi, my weekday schedule is set to start focus at 9:00, but this morning it didn't start and I had to start it by hand.

                Ortus 1.1.3 on macOS 15.1
                ```
                """),
            ]
        case "chat-working":
            return [
                ChatMessage(role: .user, content: "did tom reach out today, slack or email?"),
                ChatMessage(role: .assistant, content: "", kind: .activity(replay([
                    (0, tool("t0", "ToolSearch", #"{"query":"select:mcp__claude_ai_Slack__slack_search_users,mcp__claude_ai_Gmail__search_threads"}"#)),
                    (5, tool("t1", "mcp__claude_ai_Slack__slack_search_users", #"{"query":"Tom"}"#)),
                    (5, tool("t2", "mcp__claude_ai_Gmail__search_threads", #"{"query":"from:tom newer_than:1d"}"#)),
                ], startedAt: Date().addingTimeInterval(-7)).activity)),
            ]
        default:
            return nil
        }
    }

    private static var launchThread: ChatTurn {
        replay([
            (0, #"{"type":"system","subtype":"init"}"#),
            (3, tool("t0", "ToolSearch", #"{"query":"select:mcp__claude_ai_Slack__slack_search_public_and_private,mcp__claude_ai_Slack__slack_read_thread"}"#)),
            (4, tool("t1", "mcp__claude_ai_Slack__slack_search_public_and_private", #"{"query":"launch date in:#launch"}"#)),
            (5, result("t1")),
            (6, tool("t2", "mcp__claude_ai_Slack__slack_read_thread", #"{"channel_id":"C1","message_ts":"1"}"#)),
            (7, result("t2")),
            (7, thinkingTokens), (11, thinking),
            (11, text("""
            They moved the launch to **Thursday 6 November**, so the pricing page gets an extra week.

            ```quote
            source: slack
            place: #launch
            ---
            from: Maya Chen
            time: \(iso(daysAgo: 1, 9, 12))

            The pricing page won't be ready for Friday. Can we move the launch to next Thursday?
            ---
            from: Sam Okafor
            time: \(iso(daysAgo: 1, 9, 20))

            Thursday works for sales, as long as the email goes out on Wednesday.
            ---
            skipped: 2
            ---
            from: Tom Price
            time: \(iso(daysAgo: 1, 9, 41))

            Agreed. Let's lock Thursday 6 Nov, I'll tell the press contacts today.
            ---
            from: Maya Chen
            time: \(iso(daysAgo: 1, 9, 43))

            Locked. Updating the plan now
            ```
            """)),
            (12, end),
        ])
    }

    private static var pilotEmail: ChatTurn {
        replay([
            (0, tool("t1", "mcp__claude_ai_Gmail__search_threads", #"{"query":"from:sara pilot"}"#)),
            (2, result("t1")),
            (3, tool("t2", "mcp__claude_ai_Gmail__get_message", #"{"messageId":"1"}"#)),
            (4, result("t2")),
            (5, tool("t3", "Bash", #"{"command":"jq -r .plaintextBody ~/.claude/projects/x/tool-results/mcp-gmail.txt"}"#)),
            (6, result("t3")),
            (9, text("""
            Yes, this morning. She's in, and only wants to move the start to **12 January** so it doesn't clash with their planning week.

            ```quote
            source: gmail
            place: Re: Q1 pilot proposal
            ---
            from: Sara Conti (sara@lumen.studio)
            to: you
            time: \(iso(daysAgo: 0, 9, 14))

            Hi Federico, thanks for sending this over. We're happy to go ahead with the pilot. The only thing we'd change is the start date: could we push it to 12 January so it doesn't clash with our planning week? Everything else looks good to us, and I've shared the proposal with our finance team so the PO can go out before the holidays.
            ```
            """)),
            (10, end),
        ])
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

    static func text(_ value: String) -> String {
        let json = try! JSONSerialization.data(withJSONObject: ["type": "assistant", "message": ["content": [["type": "text", "text": value]]]])
        return String(decoding: json, as: UTF8.self)
    }

    static let thinkingTokens = #"{"type":"system","subtype":"thinking_tokens","estimated_tokens":120}"#
    static let thinking = #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":"x"}]}}"#

    /// A local time on a recent day, as Claude writes it in a quote block.
    static func iso(daysAgo: Int, _ hour: Int, _ minute: Int) -> String {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        return ISO8601DateFormatter().string(from: date)
    }

    static let end = #"{"type":"result","subtype":"success","is_error":false,"permission_denials":[]}"#
}
