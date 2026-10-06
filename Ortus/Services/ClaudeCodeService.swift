import Foundation
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

    @Published private(set) var canUndoClear = false
    private var clearedConversation: (messages: [ChatMessage], sessionID: String, started: Bool)?
    private var sessionID = UUID().uuidString
    private var hasStartedSession = false
    private var currentProcess: Process?
    private var currentTask: Task<Void, Never>?

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
        isProcessing = true
        error = nil
        errorDetails = nil
        failedPrompt = nil

        let session = sessionID
        let isFirstTurn = !hasStartedSession
        Analytics.capture("chat_message_sent", ["is_first_message": isFirstTurn])

        currentTask = Task { @MainActor in
            await runClaude(binary: binary, prompt: trimmed, sessionID: session, isFirstTurn: isFirstTurn)
            if self.error != nil { self.failedPrompt = trimmed }
            self.isProcessing = false
            self.currentProcess = nil
            self.currentTask = nil
        }
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
            "--append-system-prompt", Self.systemPrompt,
            "--permission-mode", "default",
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
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "system":
            if obj["subtype"] as? String == "init" { hasStartedSession = true }
        case "assistant":
            guard let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return }
            handleAssistantContent(content)
        case "result":
            if let isError = obj["is_error"] as? Bool, isError,
               let result = obj["result"] as? String, !result.isEmpty {
                recordFailure("Claude Code could not finish this request. Check assistant setup or retry.", details: result)
            }
        default:
            break
        }
    }

    private func handleAssistantContent(_ content: [[String: Any]]) {
        var textParts: [String] = []
        var toolUses: [(name: String, summary: String)] = []

        for block in content {
            guard let blockType = block["type"] as? String else { continue }
            if blockType == "text", let text = block["text"] as? String, !text.isEmpty {
                textParts.append(text)
            } else if blockType == "tool_use", let name = block["name"] as? String {
                let summary = summarizeTool(name: name, input: block["input"] as? [String: Any])
                toolUses.append((name: name, summary: summary))
            }
        }

        if !textParts.isEmpty {
            messages.append(ChatMessage(
                role: .assistant,
                content: textParts.joined(separator: "\n\n"),
                kind: .text
            ))
        }
        for tu in toolUses {
            messages.append(ChatMessage(
                role: .assistant,
                content: tu.summary,
                kind: .toolUse(toolName: tu.name)
            ))
        }
    }

    private func summarizeTool(name: String, input: [String: Any]?) -> String {
        // Make tool names human-readable: mcp__claude_ai_Slack__slack_search_public → "Slack · slack_search_public"
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

        if let input, !input.isEmpty {
            for key in ["query", "channel", "channel_id", "user", "user_id", "text", "name"] {
                if let value = input[key] as? String, !value.isEmpty {
                    let trimmed = value.count > 60 ? String(value.prefix(60)) + "…" : value
                    return "\(display): \(trimmed)"
                }
            }
        }
        return display
    }

    // MARK: - System prompt

    private static let systemPrompt = """
    You are the assistant inside Ortus, a macOS focus app. The user is in a focus session and the apps \
    and websites that distract them (for example Slack, email, social media) are blocked. They use this \
    chat to find information or get small tasks done without opening those apps.

    Guidelines:
    - Use whatever connected tools fit the request: Slack, email, calendar, documents, the web.
    - Be concise. Default to short answers. Skip preamble. Don't say "I'll help you with that," just do it.
    - When summarizing messages, give the gist, the sender and where it came from. Don't dump raw transcripts.
    - Resolve user IDs to display names before showing them.
    - Before anything that changes something (sending a message or email, editing a document, accepting \
      an invite), confirm the target and the content with the user first.
    - Don't pull the user back into distraction: no feeds, no unrelated highlights. Answer what they asked.
    - Format for quick scanning. Short lists when helpful. No emoji unless the user uses them first.
    """
}
