import Foundation
import OrtusCore
import SwiftUI

/// Drives the in-app chat by spawning the user's locally-installed `claude` CLI
/// as a subprocess, streaming its `--output-format stream-json` events back into
/// the chat view. Uses the user's own Claude auth + MCP configuration — Ortus
/// doesn't need an API key of its own.
@MainActor
final class ClaudeCodeService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draftText = ""
    @Published var isProcessing = false
    @Published var error: String?
    @Published private(set) var errorDetails: String?
    @Published private(set) var failedPrompt: String?

    @AppStorage("claudeBinaryPath") var claudeBinaryPath = ""

    /// The user's focus right now, in one sentence for the system prompt. Set by the
    /// app once FocusManager exists; read again on every message.
    var focusContext: () -> String? = { nil }

    /// Tools the user allowed from an inline "Allow" button, on top of `defaultAllowedTools`.
    @Published private(set) var allowedTools: [String] = UserDefaults.standard.stringArray(forKey: ClaudeCodeService.allowedToolsKey) ?? []
    private static let allowedToolsKey = "chatAllowedTools"

    /// Basic reads that run without asking. `-p` mode can't show a permission prompt,
    /// so any other tool is refused and comes back as an "Allow" button in the chat.
    private static let defaultAllowedTools = [
        "mcp__claude_ai_Gmail__search_threads",
        "mcp__claude_ai_Gmail__get_thread",
        "mcp__claude_ai_Gmail__get_message",
        "mcp__claude_ai_Gmail__list_labels",
        "mcp__claude_ai_Gmail__list_drafts",
        "mcp__claude_ai_Gmail__get_draft",
        "mcp__claude_ai_Google_Calendar__list_calendars",
        "mcp__claude_ai_Google_Calendar__list_events",
        "mcp__claude_ai_Google_Calendar__search_events",
        "mcp__claude_ai_Google_Calendar__get_event",
        "mcp__claude_ai_Google_Calendar__suggest_time",
        "mcp__claude_ai_Google_Drive__search_files",
        "mcp__claude_ai_Google_Drive__list_recent_files",
        "mcp__claude_ai_Google_Drive__get_file_metadata",
        "mcp__claude_ai_Google_Drive__read_file_content",
        "mcp__claude_ai_Slack__slack_search_public",
        "mcp__claude_ai_Slack__slack_search_public_and_private",
        "mcp__claude_ai_Slack__slack_search_channels",
        "mcp__claude_ai_Slack__slack_search_users",
        "mcp__claude_ai_Slack__slack_read_channel",
        "mcp__claude_ai_Slack__slack_read_thread",
        "mcp__claude_ai_Slack__slack_read_user_profile",
        "mcp__claude_ai_Notion__notion-search",
        "mcp__claude_ai_Notion__notion-fetch",
        "WebSearch",
    ]

    @Published private(set) var canUndoClear = false
    private var clearedConversation: (messages: [ChatMessage], sessionID: String, started: Bool)?
    private var sessionID = UUID().uuidString
    private var hasStartedSession = false
    private var currentProcess: Process?
    private var currentTask: Task<Void, Never>?
    /// The answer being streamed, and the chat rows that show it.
    private var turn: ChatTurn?
    private var activityID: UUID?
    private var answerID: UUID?

    /// `claude` resolved from the user's login-shell PATH. Filled in asynchronously
    /// by `detectIfNeeded()` so we catch installs that aren't in `defaultBinaryPaths`
    /// (nvm/fnm/asdf, custom npm prefixes, anything on the user's PATH). Published so
    /// the chat/settings UI unlocks the moment detection succeeds.
    @Published private var shellResolvedPath: String?
    private var hasRunDetection = false

    /// Common install locations to probe when the user hasn't set an explicit path.
    /// Ordered most-likely-first. Covers the native installer (`~/.local/bin`, the
    /// `curl install.sh` method), Homebrew (Apple Silicon + Intel), the legacy local
    /// install, and NixOS.
    private static let defaultBinaryPaths: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin/claude",          // native installer (curl install.sh)
            "/opt/homebrew/bin/claude",           // Homebrew (Apple Silicon)
            "/usr/local/bin/claude",              // Homebrew (Intel) / /usr/local
            "\(home)/.claude/local/claude",       // legacy local install / migrate-installer
            "/run/current-system/sw/bin/claude",  // NixOS
        ]
    }()

    var resolvedBinaryPath: String? {
        if !claudeBinaryPath.isEmpty, FileManager.default.isExecutableFile(atPath: claudeBinaryPath) {
            return claudeBinaryPath
        }
        for candidate in Self.defaultBinaryPaths {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return shellResolvedPath
    }

    var isConfigured: Bool {
        resolvedBinaryPath != nil
    }

    /// Probe the user's login shell for `claude` once, off the main thread. Static
    /// paths are checked first (synchronous, instant); the shell probe only runs as a
    /// fallback when none of them hit. Safe to call repeatedly — it no-ops after the
    /// first run unless `redetect()` resets it.
    func detectIfNeeded() {
        guard !hasRunDetection else { return }
        hasRunDetection = true
        // A static path (or user override) already resolves — no need to spawn a shell.
        if resolvedBinaryPath != nil { return }
        Task.detached(priority: .utility) {
            let path = Self.resolveViaLoginShell()
            if let path {
                await MainActor.run { self.shellResolvedPath = path }
            }
        }
    }

    /// Force a fresh detection pass — used when the user may have just installed
    /// Claude Code while the app was already running.
    func redetect() {
        hasRunDetection = false
        shellResolvedPath = nil
        detectIfNeeded()
    }

    /// Ask the user's login + interactive shell where `claude` lives. Using `-ilc`
    /// sources the same profile files the user's terminal does, so PATH additions
    /// from nvm/fnm/asdf/custom npm prefixes are visible — the common cases the
    /// static path list can't anticipate. Bounded by a watchdog so a slow or noisy
    /// shell profile can't hang detection.
    nonisolated private static func resolveViaLoginShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", "command -v claude"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Don't let an interactive profile that prompts or stalls hang us forever.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)

        // Read before waiting to avoid a full-pipe deadlock on chatty profiles.
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return nil }

        // `command -v` prints the resolved path; profiles may add noise, so take the
        // first line that's an absolute path to an executable file.
        for line in output.split(separator: "\n") {
            let candidate = line.trimmingCharacters(in: .whitespaces)
            if candidate.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Public API

    func retryLastMessage() {
        guard let prompt = failedPrompt, !isProcessing else { return }
        sendMessage(prompt, isRetry: true)
    }

    func sendMessage(_ text: String, isRetry: Bool = false) {
        guard !isProcessing else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let binary = resolvedBinaryPath else {
            failedPrompt = trimmed
            recordFailure("Claude Code could not be found. Open assistant setup to connect your installation.")
            return
        }

        clearedConversation = nil; canUndoClear = false
        if !isRetry { messages.append(ChatMessage(role: .user, content: trimmed)) }
        let newTurn = ChatTurn(startedAt: Date())
        let activity = ChatMessage(role: .assistant, content: "", kind: .activity(newTurn.activity))
        messages.append(activity)
        turn = newTurn; activityID = activity.id; answerID = nil
        isProcessing = true
        error = nil
        errorDetails = nil
        failedPrompt = nil

        let session = sessionID
        let isFirstTurn = !hasStartedSession
        Analytics.capture("chat_message_sent", ["is_first_message": isFirstTurn])

        currentTask = Task { @MainActor in
            await runClaude(binary: binary, prompt: trimmed, sessionID: session, isFirstTurn: isFirstTurn)
            self.updateTurn { $0.finish(at: Date(), stopped: Task.isCancelled) }
            if self.error != nil { self.failedPrompt = trimmed }
            self.isProcessing = false
            self.currentProcess = nil
            self.currentTask = nil
        }
    }

    /// Remembers the tool and asks Claude to pick up where the refusal stopped it.
    func allowTool(_ name: String) {
        guard !isProcessing else { return }
        if !allowedTools.contains(name) {
            allowedTools.append(name)
            UserDefaults.standard.set(allowedTools, forKey: Self.allowedToolsKey)
        }
        Analytics.capture("chat_tool_allowed", ["tool": name])
        sendMessage("I allowed \(name). Try again.", isRetry: true)
    }

    func stop() {
        currentProcess?.terminate()
        currentTask?.cancel()
    }

    func clearConversation() {
        guard !isProcessing else { return }
        clearedConversation = (messages, sessionID, hasStartedSession)
        canUndoClear = !messages.isEmpty
        stop()
        Analytics.capture("chat_cleared", ["message_count": messages.count])
        messages.removeAll()
        turn = nil; activityID = nil; answerID = nil
        sessionID = UUID().uuidString
        hasStartedSession = false
        error = nil
        errorDetails = nil
        failedPrompt = nil
    }

    func undoClear() {
        guard !isProcessing, messages.isEmpty, let previous = clearedConversation else { return }
        messages = previous.messages; sessionID = previous.sessionID; hasStartedSession = previous.started
        clearedConversation = nil; canUndoClear = false
    }

    // MARK: - Subprocess

    private func runClaude(binary: String, prompt: String, sessionID: String, isFirstTurn: Bool) async {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: binary)
        process.standardOutput = stdout
        process.standardError = stderr
        // Carry through HOME / PATH / etc so claude finds its config and the user's auth.
        process.environment = ProcessInfo.processInfo.environment

        var args = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--model", "claude-sonnet-5-5",
            "--effort", "low",
            "--append-system-prompt", Self.systemPrompt(now: Date(), focus: focusContext()),
            "--permission-mode", "default",
            "--allowedTools", (Self.defaultAllowedTools + allowedTools).joined(separator: ","),
        ]
        if isFirstTurn {
            args.append(contentsOf: ["--session-id", sessionID])
        } else {
            args.append(contentsOf: ["--resume", sessionID])
        }
        process.arguments = args

        currentProcess = process

        do {
            try process.run()
        } catch {
            recordFailure("Claude Code could not start. Check its location in assistant setup, then retry.", details: error.localizedDescription)
            return
        }

        // Drain stderr concurrently so verbose errors cannot fill the pipe and stall Claude.
        let stderrReader = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }

        // Stream stdout line by line. Each line is a JSON event.
        do {
            for try await line in stdout.fileHandleForReading.bytes.lines {
                if Task.isCancelled { break }
                handleStreamLine(line)
            }
        } catch {
            // Pipe read error — usually means cancellation. Fall through to exit handling.
        }

        // Drain whatever's left and wait for the process to finish.
        process.waitUntilExit()

        let stderrData = await stderrReader.value
        if process.terminationStatus != 0 && !Task.isCancelled && error == nil {
            let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = stderrText.isEmpty
                ? "claude exited with status \(process.terminationStatus)."
                : stderrText
            recordFailure("Claude Code could not finish this request. Check your connection and Claude sign-in, then retry.", details: message)
        }
    }

    private func recordFailure(_ message: String, details: String? = nil) {
        error = message
        errorDetails = details
        messages.append(ChatMessage(role: .assistant, content: message, kind: .error))
    }

    // MARK: - Stream parsing

    private func handleStreamLine(_ line: String) {
        guard !line.isEmpty else { return }
        updateTurn { $0.consume(line, at: Date()) }
    }

    /// Applies a change to the current answer and mirrors it into the chat rows:
    /// the activity row updates in place, the answer appears under it (and leaves
    /// again if it turns out to be narration before a tool call), and refusals and
    /// errors are added once the answer is finished.
    private func updateTurn(_ change: (inout ChatTurn) -> Void) {
        guard var current = turn else { return }
        let wasFinished = current.isFinished
        change(&current)
        turn = current
        if current.didStartSession { hasStartedSession = true }

        guard let activityIndex = messages.firstIndex(where: { $0.id == activityID }) else { return }
        messages[activityIndex].kind = .activity(current.activity)

        let answerIndex = messages.firstIndex { $0.id == answerID }
        switch (answerIndex, current.answer.isEmpty) {
        case (nil, false):
            let answer = ChatMessage(role: .assistant, content: current.answer)
            messages.insert(answer, at: activityIndex + 1)
            answerID = answer.id
        case (let index?, false):
            if messages[index].content != current.answer { messages[index].content = current.answer }
        case (let index?, true):
            messages.remove(at: index)
            answerID = nil
        case (nil, true):
            break
        }

        guard current.isFinished, !wasFinished else { return }
        if let failure = current.failure {
            recordFailure("Claude Code could not finish this request. Check assistant setup or retry.", details: failure)
        }
        for name in current.deniedTools where !allowedTools.contains(name) {
            messages.append(ChatMessage(role: .assistant, content: Self.displayName(for: name), kind: .permissionRequest(toolName: name)))
        }
    }

    /// Make tool names human-readable: mcp__claude_ai_Slack__slack_search_public → "Slack · slack_search_public"
    private static func displayName(for name: String) -> String {
        var display = name
        if let prefixRange = display.range(of: "mcp__") {
            display = String(display[prefixRange.upperBound...])
            if let serverRange = display.range(of: "__") {
                let server = display[..<serverRange.lowerBound]
                    .replacingOccurrences(of: "claude_ai_", with: "")
                    .replacingOccurrences(of: "plugin_", with: "")
                    .replacingOccurrences(of: "_", with: " ")
                let tool = String(display[serverRange.upperBound...])
                display = "\(server) · \(tool)"
            }
        }
        return display
    }

    // MARK: - System prompt

    /// Rebuilt for every message: each one starts a new `claude` process (resuming the
    /// same session), so the time and the focus state are always current.
    static func systemPrompt(now: Date, focus: String?) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        let today = "Right now it is \(clock.string(from: now)) (\(TimeZone.current.identifier))."
        return """
        You are the assistant inside Ortus, a macOS focus app. The apps and websites that distract the user \
        (for example Slack, email, social media) are blocked while they focus. They use this chat to find \
        information or get small tasks done without opening those apps. Answer what they asked and protect \
        their attention.

        \(today)
        \(focus ?? "")

        Guidelines:
        - Use whatever connected tools fit the request: Slack, email, calendar, documents, the web.
        - Answer in the first sentence. Skip preamble. Don't narrate what you're about to do.
        - Show only what matters for the question. If the answer is no or nothing, say so in one line and \
        stop: don't list what else you came across (other channels, newsletters, promotions, past events, \
        "they did post elsewhere…").
        - For "anything urgent?" questions, mention only what needs the user before their session ends or \
        today. Everything else is one short closing line at most, without names.
        - Resolve user IDs to display names before showing them.
        - Before anything that changes something (sending a message or email, editing a document, accepting \
        an invite), confirm the target and the content with the user first.
        - If a tool is refused because the user hasn't allowed it yet, say so in one short line: they can \
        allow it with the button under your reply. Don't send them to connector settings.

        Formatting (the chat panel is narrow, about 50 characters per line):
        - Short paragraphs. A bullet list only for three or more parallel items. Bold sparingly, for names \
        or the key fact.
        - No headings, no tables, no emoji unless the user uses them first.
        - Times in the user's local time, relative when close ("yesterday at 11:37", "Thursday at 9:00"). \
        Never write time zone names.

        Quoting messages: when you show what someone actually wrote (a Slack message or thread, an email, a \
        social post), put it in a quote block so Ortus shows it as a card. Text inside is copied verbatim \
        from the tool result; shorten long text with "…" but never reword it. When the user asks what a \
        message, email or post said, quote it rather than paraphrasing; open the full message if you only \
        have a preview. Quote only the messages that answer the question, usually one to four; summarize \
        the rest in a sentence outside the block. Don't repeat in prose or bullets what the quote already \
        says. Format:

        ```quote
        source: slack
        place: #general
        ---
        from: Maya Chen
        time: 2026-10-25T10:12:00+00:00

        The pricing page won't be ready for Friday…
        ---
        skipped: 4
        ---
        from: Tom Price
        time: 2026-10-25T10:37:00+00:00

        Agreed
        ```

        - source is slack, gmail, linkedin, x or other. place is the channel ("#general", "DM with Maya"), \
        the email subject, or the site.
        - One section per message, oldest first, separated by "---". Header lines, then a blank line, then \
        the text.
        - For a thread, include the parent and only the replies that matter; a "skipped: N" section marks \
        replies you left out (don't explain the skipping in prose).
        - Emails may add "to:" under "from:". Posts may add "about:" with the author's headline.
        - Times are ISO 8601 with offset, copied from the tool result.
        """
    }
}
