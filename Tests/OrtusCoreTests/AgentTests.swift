import Foundation
import OrtusCore

/// Codex lines follow the types in codex-rs/exec/src/exec_events.rs (made-up content).
/// Sign-in outputs copy what `claude auth status --json` and `codex login status` print.
struct AgentTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func runAll() throws {
        let checks = AgentTests()
        checks.codexRunNamesStepsLikeClaudeCode()
        checks.codexNarrationFailuresAndAppNames()
        checks.codexTurnFailuresAndUnknownEvents()
        checks.claudeCodeFormatIsUnchanged()
        checks.parsesClaudeSignIn()
        checks.parsesCodexSignInAndSignedOutErrors()
        checks.findsTheSignInPage()
        checks.buildsCodexCommandLines()
        try checks.findsTheCopyInsideDesktopApps()
    }

    private func codex(_ events: [(Double, String)]) -> ChatTurn {
        var turn = ChatTurn(startedAt: start, format: .codex)
        for (seconds, line) in events { turn.consume(line, at: start.addingTimeInterval(seconds)) }
        return turn
    }
    private func item(_ event: String, _ json: String) -> String { #"{"type":"item.\#(event)","item":\#(json)}"# }
    private func message(_ id: String, _ text: String) -> String {
        item("completed", #"{"id":"\#(id)","type":"agent_message","text":"\#(text)"}"#)
    }
    private func command(_ id: String, _ event: String, exit: String = "null", status: String = "in_progress") -> String {
        item(event, #"{"id":"\#(id)","type":"command_execution","command":"/bin/zsh -lc ls","aggregated_output":"","exit_code":\#(exit),"status":"\#(status)"}"#)
    }
    private func mcp(_ id: String, _ event: String, server: String, tool: String, arguments: String = "{}", error: String = "null", status: String = "in_progress") -> String {
        item(event, #"{"id":"\#(id)","type":"mcp_tool_call","server":"\#(server)","tool":"\#(tool)","arguments":\#(arguments),"result":null,"error":\#(error),"status":"\#(status)"}"#)
    }
    private let done = #"{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}"#

    // MARK: - Codex events

    func codexRunNamesStepsLikeClaudeCode() {
        let run: [(Double, String)] = [
            (0, #"{"type":"thread.started","thread_id":"019ab3c2-7f10-7a41-9c2e-5d8e0f6a1b23"}"#),
            (1, #"{"type":"turn.started"}"#),
            (4, #"{"type":"item.completed","item":{"id":"item_0","type":"reasoning","text":"**Searching Slack**"}}"#),
            (4, #"{"type":"item.started","item":{"id":"item_1","type":"mcp_tool_call","server":"slack","tool":"search_messages","arguments":{"query":"launch date"},"result":null,"error":null,"status":"in_progress"}}"#),
            (6, ##"{"type":"item.completed","item":{"id":"item_1","type":"mcp_tool_call","server":"slack","tool":"search_messages","arguments":{"query":"launch date"},"result":{"content":[{"type":"text","text":"#launch: moved to 3 Dec"}]},"error":null,"status":"completed"}}"##),
            (7, #"{"type":"item.completed","item":{"id":"item_2","type":"agent_message","text":"The launch moved to 3 December (per #launch)."}}"#),
            (7, #"{"type":"turn.completed","usage":{"input_tokens":18234,"cached_input_tokens":12032,"output_tokens":214,"reasoning_output_tokens":96}}"#),
        ]
        var live = ChatTurn(startedAt: start, format: .codex)
        for (seconds, line) in run.prefix(4) { live.consume(line, at: start.addingTimeInterval(seconds)) }
        expect(live.didStartSession && live.threadID == "019ab3c2-7f10-7a41-9c2e-5d8e0f6a1b23")
        expect(live.activity.progress == "Searching Slack" && !live.isFinished)

        let turn = codex(run)
        expect(turn.isFinished && turn.failure == nil)
        expect(turn.answer == "The launch moved to 3 December (per #launch).")
        expect(turn.activity.steps.map(\.kind) == [.thought, .tool])
        expect(turn.activity.steps[0].title == "Thought for 3s") // reasoning has no start: timed from turn.started
        expect(turn.activity.toolSteps.map(\.title) == ["Searched Slack “launch date”"])
        expect(turn.activity.toolSteps.allSatisfy { $0.status == .done })
        expect(turn.activity.summary == "Searched Slack · 1 step")

        // A web search's query only arrives when it's done.
        let search = codex([
            (0, item("started", #"{"id":"item_0","type":"web_search","query":"","action":{"type":"other"}}"#)),
            (2, item("completed", #"{"id":"item_0","type":"web_search","query":"ortus pricing","action":{"type":"search","query":"ortus pricing"}}"#)),
            (3, done),
        ])
        expect(search.activity.toolSteps.map(\.title) == ["Searched the web “ortus pricing”"])
        expect(search.activity.toolSteps.first?.status == .done && search.activity.summary == "Searched the web · 1 step")
    }

    func codexNarrationFailuresAndAppNames() {
        let narrated = codex([
            (0, message("item_0", "Let me check your files.")),
            (1, command("item_1", "started")), (2, command("item_1", "completed", exit: "0", status: "completed")),
            (3, message("item_2", "You have two files.")), (3, done),
        ])
        expect(narrated.answer == "You have two files.")
        expect(narrated.activity.steps.map(\.kind) == [.note, .tool])
        expect(narrated.activity.steps.map(\.title) == ["Let me check your files.", "Ran a command"])
        expect(!narrated.activity.hasProblem)

        // A failing exit code fails the step even when the status says completed, and an
        // end without a start still shows.
        let failed = codex([
            (0, command("item_0", "started")), (1, command("item_0", "completed", exit: "1", status: "failed")),
            (1, command("item_1", "completed", exit: "2", status: "completed")), (2, done),
        ])
        expect(failed.activity.toolSteps.map(\.status) == [.failed, .failed] && failed.activity.hasProblem)

        // ChatGPT's connected apps arrive as one server; the tool name says which app.
        let apps = codex([
            (0, mcp("item_0", "started", server: "codex_apps", tool: "gmail_search_emails", arguments: #"{"query":"from:maya"}"#)),
            (1, mcp("item_0", "completed", server: "codex_apps", tool: "gmail_search_emails", arguments: #"{"query":"from:maya"}"#, status: "completed")),
            (2, mcp("item_1", "completed", server: "codex_apps", tool: "slack_send_message", error: #"{"message":"channel_not_found"}"#, status: "completed")),
            (3, done),
        ])
        expect(apps.activity.toolSteps.map(\.title) == ["Searched Gmail “from:maya”", "Sent a message in Slack"])
        expect(apps.activity.toolSteps.map(\.status) == [.done, .failed])
        expect(apps.activity.summary == "Searched Gmail and Slack · 2 steps")
    }

    func codexTurnFailuresAndUnknownEvents() {
        let withMessage = codex([(0, #"{"type":"turn.failed","error":{"message":"You've hit your usage limit."}}"#)])
        expect(withMessage.isFinished && withMessage.failure == "You've hit your usage limit.")
        let fromError = codex([
            (0, #"{"type":"error","message":"stream disconnected before completion"}"#),
            (1, #"{"type":"turn.failed","error":{}}"#),
        ])
        expect(fromError.failure == "stream disconnected before completion")
        expect(codex([(0, #"{"type":"turn.failed"}"#)]).failure == "Codex stopped with an error.")
        // An error alone doesn't end the turn: Codex may retry.
        expect(!codex([(0, #"{"type":"error","message":"Reconnecting... 1/5"}"#)]).isFinished)

        let noisy = codex([
            (0, "Reading prompt from stdin..."),
            (0, #"{"type":"turn.started"}"#),
            (1, item("started", #"{"id":"item_0","type":"todo_list","items":[{"text":"Look","completed":false}]}"#)),
            (1, item("updated", #"{"id":"item_0","type":"todo_list","items":[{"text":"Look","completed":true}]}"#)),
            (2, item("completed", #"{"id":"item_1","type":"file_change","changes":[{"path":"a.txt","kind":"add"}],"status":"completed"}"#)),
            (2, item("completed", #"{"id":"item_2","type":"error","message":"model rerouted"}"#)),
            (2, item("completed", #"{"id":"item_3","type":"collab_tool_call","tool":"spawn_agent","status":"completed"}"#)),
            (2, item("completed", #"{"id":"item_4","type":"something_new","x":1}"#)),
            (2, #"{"type":"thread.renamed","name":"x"}"#),
            (3, message("item_5", "Done.")), (3, done),
        ])
        expect(noisy.activity.steps.isEmpty && noisy.answer == "Done." && noisy.isFinished && noisy.failure == nil)
    }

    func claudeCodeFormatIsUnchanged() {
        var claude = ChatTurn(startedAt: start)
        claude.consume(#"{"type":"thread.started","thread_id":"t"}"#, at: start)
        claude.consume(#"{"type":"turn.completed"}"#, at: start)
        expect(!claude.didStartSession && claude.threadID == nil && !claude.isFinished)
        claude.consume(#"{"type":"system","subtype":"init","session_id":"s"}"#, at: start)
        expect(claude.didStartSession && claude.threadID == nil)

        var codexTurn = ChatTurn(startedAt: start, format: .codex)
        codexTurn.consume(#"{"type":"system","subtype":"init"}"#, at: start)
        codexTurn.consume(#"{"type":"result","is_error":true,"result":"x"}"#, at: start)
        expect(!codexTurn.didStartSession && !codexTurn.isFinished)
    }

    // MARK: - Sign-in

    func parsesClaudeSignIn() {
        let signedIn = #"{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"max","email":"x@y.com","orgId":"o"}"#
        expect(AgentSignIn.parseClaude(output: signedIn, exitCode: 0) == .signedIn(email: "x@y.com", plan: "Max plan"))
        let pretty = """
        Update available: 2.1.331 {run claude update}
        {
          "loggedIn": true,
          "authMethod": "claude.ai",
          "subscriptionType": "pro"
        }
        """
        expect(AgentSignIn.parseClaude(output: pretty, exitCode: 0) == .signedIn(email: nil, plan: "Pro plan"))
        expect(AgentSignIn.parseClaude(output: #"{"loggedIn":false,"authMethod":"none"}"# + "\n", exitCode: 1) == .signedOut)
        for (subscription, plan) in [("team", "Team plan"), ("enterprise", "Enterprise plan"), ("ultra", "Ultra plan"), ("MAX", "Max plan")] {
            let json = #"{"loggedIn":true,"subscriptionType":"\#(subscription)","email":"a@b.co"}"#
            expect(AgentSignIn.parseClaude(output: json, exitCode: 0) == .signedIn(email: "a@b.co", plan: plan))
        }
        expect(AgentSignIn.parseClaude(output: #"{"loggedIn":true,"authMethod":"api_key","subscriptionType":"","email":""}"#, exitCode: 0) == .signedIn(email: nil, plan: nil))
        expect(AgentSignIn.parseClaude(output: "error: unknown command 'auth'\n", exitCode: 1) == .unknown("error: unknown command 'auth'"))
        expect(AgentSignIn.parseClaude(output: "", exitCode: 1) == .unknown("No answer (exit code 1)"))
        expect(AgentSignIn.parseClaude(output: #"{"status":"ok"}"#, exitCode: 0) == .unknown(#"{"status":"ok"}"#))
    }

    func parsesCodexSignInAndSignedOutErrors() {
        expect(AgentSignIn.parseCodex(output: "Logged in using ChatGPT\n", exitCode: 0) == .signedIn(email: nil, plan: "ChatGPT"))
        expect(AgentSignIn.parseCodex(output: "Logged in using an API key - sk-proj-***ABCDE\n", exitCode: 0) == .signedIn(email: nil, plan: nil))
        expect(AgentSignIn.parseCodex(output: "Not logged in\n", exitCode: 1) == .signedOut)
        expect(AgentSignIn.parseCodex(output: "Not logged in\n", exitCode: 0) == .signedOut)
        expect(AgentSignIn.parseCodex(output: "Error checking login status: bad file\n", exitCode: 1) == .signedOut)

        for signedOut in [
            "Not logged in · Please run /login",
            "Invalid API key · Please run /login",
            "OAuth token has expired. Please obtain a new token or refresh your existing token.",
            "unexpected status 401 Unauthorized: Missing bearer authentication in header",
            "Your access token could not be refreshed because your refresh token was already used. Please log out and sign in again.",
            "error: token_expired",
            "Not logged in. Run `codex login` first.",
        ] { expect(AgentSignIn.meansSignedOut(signedOut)) }
        for other in ["Overloaded", "You've hit your usage limit.", "stream disconnected before completion", ""] {
            expect(!AgentSignIn.meansSignedOut(other))
        }
    }

    func findsTheSignInPage() {
        let claude = "Opening browser to sign in…\nIf the browser didn't open, visit: https://claude.ai/oauth/authorize?code=true&client_id=abc&state=xyz\n"
        expect(AgentSignIn.signInURL(in: claude)?.absoluteString == "https://claude.ai/oauth/authorize?code=true&client_id=abc&state=xyz")
        let codex = """
        Starting local login server on http://localhost:1455.
        If your browser did not open, navigate to this URL to authenticate:

        https://auth.openai.com/oauth/authorize?response_type=code&client_id=app_X&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback

        On a remote or headless machine? Use `codex login --device-auth` instead.
        """
        expect(AgentSignIn.signInURL(in: codex)?.host == "auth.openai.com")
        expect(AgentSignIn.signInURL(in: "Go to \u{1B}[1mhttps://example.com/login\u{1B}[0m.")?.absoluteString == "https://example.com/login")
        expect(AgentSignIn.signInURL(in: "(see https://example.com/a).")?.absoluteString == "https://example.com/a")
        expect(AgentSignIn.signInURL(in: "Waiting for http://127.0.0.1:54545/callback") == nil)
        expect(AgentSignIn.signInURL(in: "Login successful") == nil)
    }

    // MARK: - Commands

    func buildsCodexCommandLines() {
        expect(AgentCommand.tomlString(#"say "hi" to C:\temp"#) == #""say \"hi\" to C:\\temp""#)
        expect(AgentCommand.tomlString("one\ntwo\tthree\r\n") == #""one\ntwo\tthree\r\n""#)
        expect(AgentCommand.tomlString("bell\u{07} del\u{7F} esc\u{1B} \u{08}\u{0C}") == #""bell\u0007 del\u007F esc\u001B \b\f""#)
        expect(AgentCommand.tomlString("🌅 café — ok") == "\"🌅 café — ok\"")
        expect(AgentCommand.tomlString("") == "\"\"")

        let flags = ["exec", "--json", "--dangerously-bypass-approvals-and-sandbox", "--skip-git-repo-check", "-C", "/tmp/agent",
                     "-c", #"model_reasoning_effort="low""#, "-c", #"developer_instructions="Be brief.\nDraft first.""#]
        let first = AgentCommand.codexTurn(prompt: "What's new?", systemPrompt: "Be brief.\nDraft first.", threadID: nil, workingDirectory: "/tmp/agent")
        expect(first == flags + ["What's new?"])
        let next = AgentCommand.codexTurn(prompt: "And Gmail?", systemPrompt: "Be brief.\nDraft first.", threadID: "019ab3c2", workingDirectory: "/tmp/agent")
        expect(next == flags + ["resume", "019ab3c2", "And Gmail?"])
    }

    // MARK: - Finding the CLI

    func findsTheCopyInsideDesktopApps() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("OrtusAgentTests-\(UUID().uuidString)").path
        defer { try? fileManager.removeItem(atPath: root) }
        func file(_ path: String, executable: Bool = true) throws {
            try fileManager.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            expect(fileManager.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: executable ? 0o755 : 0o644]))
        }
        func claudeCode(_ home: String) -> String { "\(root)/\(home)/Library/Application Support/Claude/claude-code" }

        expect(AgentLocator.cliCandidates(.claudeCode, home: "/Users/me").first == "/Users/me/.local/bin/claude")
        expect(AgentLocator.cliCandidates(.claudeCode, home: "/Users/me").count == 5)
        expect(AgentLocator.cliCandidates(.codex, home: "/Users/me") == ["/Users/me/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"])
        expect(AgentEngine.allCases.map(\.name) == ["Claude Code", "Codex"] && AgentEngine.codex.binaryName == "codex")

        // Today's layout. 2.1.330 is newer than 2.1.9; names that aren't versions, a copy
        // that can't run and a folder named claude are skipped.
        let today = claudeCode("today")
        try file("\(today)/2.1.9/abc123def456/claude.app/Contents/MacOS/claude")
        try file("\(today)/2.1.330/4262a1273231/claude.app/Contents/MacOS/claude")
        try file("\(today)/10.0.0-beta/claude")
        try file("\(today)/latest/claude")
        try file("\(today)/3.0.0/claude", executable: false)
        try fileManager.createDirectory(atPath: "\(today)/4.0.0/claude", withIntermediateDirectories: true)
        expect(AgentLocator.desktopCopy(.claudeCode, home: "\(root)/today") == "\(today)/2.1.330/4262a1273231/claude.app/Contents/MacOS/claude")

        // Older layouts.
        try file("\(claudeCode("older"))/2.0.1/claude.app/Contents/MacOS/claude")
        expect(AgentLocator.desktopCopy(.claudeCode, home: "\(root)/older") == "\(claudeCode("older"))/2.0.1/claude.app/Contents/MacOS/claude")
        try file("\(claudeCode("oldest"))/1.0.0/claude")
        expect(AgentLocator.desktopCopy(.claudeCode, home: "\(root)/oldest") == "\(claudeCode("oldest"))/1.0.0/claude")
        expect(AgentLocator.desktopCopy(.claudeCode, home: "\(root)/nobody") == nil)

        // Codex: the system Applications folder first, then the user's.
        let apps = "\(root)/Applications", home = "\(root)/codex"
        expect(AgentLocator.desktopCopy(.codex, home: home, applications: [apps]) == nil)
        try file("\(home)/Applications/Codex.app/Contents/Resources/codex")
        expect(AgentLocator.desktopCopy(.codex, home: home, applications: [apps]) == "\(home)/Applications/Codex.app/Contents/Resources/codex")
        try file("\(apps)/ChatGPT.app/Contents/Resources/codex", executable: false)
        expect(AgentLocator.desktopCopy(.codex, home: home, applications: [apps]) == "\(home)/Applications/Codex.app/Contents/Resources/codex")
        try file("\(apps)/ChatGPT.app/Contents/Resources/codex-cli/bin/codex")
        expect(AgentLocator.desktopCopy(.codex, home: home, applications: [apps]) == "\(apps)/ChatGPT.app/Contents/Resources/codex-cli/bin/codex")
        try file("\(apps)/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        expect(AgentLocator.desktopCopy(.codex, home: home, applications: [apps]) == "\(apps)/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        expect(AgentLocator.desktopCopy(.claudeCode, home: home, applications: [apps]) == nil)
    }
}
