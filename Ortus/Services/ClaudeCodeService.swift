import Foundation
import SwiftUI

/// Drives the in-app chat by spawning the user's locally-installed `claude` CLI
/// as a subprocess, streaming its `--output-format stream-json` events back into
/// the chat view. Uses the user's own Claude auth + MCP configuration — Ortus
/// doesn't need an API key of its own.
@MainActor
final class ClaudeCodeService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing = false
    @Published var error: String?

    @AppStorage("claudeBinaryPath") var claudeBinaryPath = ""

    private var sessionID = UUID().uuidString
    private var hasStartedSession = false
    private var currentProcess: Process?
    private var currentTask: Task<Void, Never>?

    /// Common Homebrew / system locations to probe when the user hasn't set an explicit path.
    private static let defaultBinaryPaths = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "/run/current-system/sw/bin/claude",
    ]

    var resolvedBinaryPath: String? {
        if !claudeBinaryPath.isEmpty, FileManager.default.isExecutableFile(atPath: claudeBinaryPath) {
            return claudeBinaryPath
        }
        for candidate in Self.defaultBinaryPaths {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    var isConfigured: Bool {
        resolvedBinaryPath != nil
    }

    // MARK: - Public API

    func sendMessage(_ text: String) {
        guard !isProcessing else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let binary = resolvedBinaryPath else {
            messages.append(ChatMessage(
                role: .assistant,
                content: "Claude Code isn't installed at a known location. Install it (https://docs.claude.com/claude-code) or set its path in Settings.",
                kind: .error
            ))
            return
        }

        messages.append(ChatMessage(role: .user, content: trimmed))
        isProcessing = true
        error = nil

        let session = sessionID
        let isFirstTurn = !hasStartedSession
        hasStartedSession = true

        currentTask = Task { @MainActor in
            await runClaude(binary: binary, prompt: trimmed, sessionID: session, isFirstTurn: isFirstTurn)
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
        stop()
        messages.removeAll()
        sessionID = UUID().uuidString
        hasStartedSession = false
        error = nil
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
            "--model", "sonnet",
            "--append-system-prompt", Self.systemPrompt,
            "--permission-mode", "bypassPermissions",
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
            messages.append(ChatMessage(
                role: .assistant,
                content: "Failed to launch claude: \(error.localizedDescription)",
                kind: .error
            ))
            return
        }

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

        if process.terminationStatus != 0 && !Task.isCancelled {
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = stderrText.isEmpty
                ? "claude exited with status \(process.terminationStatus)."
                : stderrText
            messages.append(ChatMessage(role: .assistant, content: message, kind: .error))
        }
    }

    // MARK: - Stream parsing

    private func handleStreamLine(_ line: String) {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "assistant":
            guard let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return }
            handleAssistantContent(content)
        case "result":
            if let isError = obj["is_error"] as? Bool, isError,
               let result = obj["result"] as? String, !result.isEmpty {
                messages.append(ChatMessage(role: .assistant, content: result, kind: .error))
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
                    return "\(display) — \(trimmed)"
                }
            }
        }
        return display
    }

    // MARK: - System prompt

    private static let systemPrompt = """
    You are the AI assistant inside Ortus, a macOS focus app. The user is currently in Ortus mode \
    (a deep-focus session) and Slack is blocked on their machine. They're using this chat to retrieve \
    information from Slack or perform Slack actions without unblocking Slack.

    Guidelines:
    - Use the Slack MCP (tools starting with `mcp__claude_ai_Slack__`) for all Slack operations.
    - Do not use other MCPs or tools unless the user explicitly asks for them.
    - Be concise. Default to short answers. Skip preamble — don't say "I'll help you with that," just do it.
    - When summarizing messages, give the gist + sender + channel. Don't dump raw transcripts.
    - Resolve user IDs to display names before showing them.
    - Before any mutating Slack action (send message, schedule message, edit canvas), confirm the target \
      channel/user and the content with the user first.
    - Format for quick scanning. Short lists when helpful. No emoji unless the user uses them first.
    """
}
