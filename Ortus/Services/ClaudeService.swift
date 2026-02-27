import Foundation

@MainActor
final class ClaudeService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing = false

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-5-20250929"
    private let maxIterations = 10

    private var conversationHistory: [[String: Any]] = []

    var slackService: SlackService?

    private var apiKey: String? {
        KeychainService.load(.claudeAPIKey)
    }

    var isConfigured: Bool {
        apiKey != nil && !(apiKey?.isEmpty ?? true)
    }

    func sendMessage(_ text: String) async {
        guard let apiKey, !apiKey.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        conversationHistory.append(["role": "user", "content": text])
        isProcessing = true

        defer { isProcessing = false }

        do {
            try await agentLoop(apiKey: apiKey)
        } catch {
            let errorMessage = ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)")
            messages.append(errorMessage)
        }
    }

    func clearConversation() {
        messages.removeAll()
        conversationHistory.removeAll()
    }

    // MARK: - Agentic Loop

    private func agentLoop(apiKey: String) async throws {
        for _ in 0..<maxIterations {
            let response = try await callClaude(apiKey: apiKey)

            guard let content = response["content"] as? [[String: Any]] else {
                throw ClaudeError.invalidResponse
            }

            var textParts: [String] = []
            var toolUseCalls: [(id: String, name: String, input: [String: Any])] = []

            for block in content {
                if let type = block["type"] as? String {
                    if type == "text", let text = block["text"] as? String {
                        textParts.append(text)
                    } else if type == "tool_use",
                              let id = block["id"] as? String,
                              let name = block["name"] as? String,
                              let input = block["input"] as? [String: Any] {
                        toolUseCalls.append((id: id, name: name, input: input))
                    }
                }
            }

            // Add assistant message to conversation
            conversationHistory.append(["role": "assistant", "content": content])

            // If there's text and no tool calls, we're done
            if !textParts.isEmpty && toolUseCalls.isEmpty {
                let assistantMessage = ChatMessage(role: .assistant, content: textParts.joined(separator: "\n"))
                messages.append(assistantMessage)
                return
            }

            // If there are tool calls, execute them
            if !toolUseCalls.isEmpty {
                // Show any text before tool execution
                if !textParts.isEmpty {
                    let thinkingMessage = ChatMessage(role: .assistant, content: textParts.joined(separator: "\n"))
                    messages.append(thinkingMessage)
                }

                var toolResults: [[String: Any]] = []
                for call in toolUseCalls {
                    let result = await executeToolCall(name: call.name, input: call.input)
                    toolResults.append([
                        "type": "tool_result",
                        "tool_use_id": call.id,
                        "content": result,
                    ])
                }

                conversationHistory.append(["role": "user", "content": toolResults])
                continue
            }

            // Stop reason is end_turn with no text
            let stopReason = response["stop_reason"] as? String
            if stopReason == "end_turn" {
                if textParts.isEmpty {
                    let msg = ChatMessage(role: .assistant, content: "I processed your request but have no additional information to share.")
                    messages.append(msg)
                }
                return
            }
        }

        let msg = ChatMessage(role: .assistant, content: "I reached the maximum number of tool calls. Here's what I found so far.")
        messages.append(msg)
    }

    // MARK: - Claude API Call

    private func callClaude(apiKey: String) async throws -> [String: Any] {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "tools": SlackTools.definitions,
            "messages": conversationHistory,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.apiError(httpResponse.statusCode, errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.invalidResponse
        }

        return json
    }

    // MARK: - Tool Execution

    private func executeToolCall(name: String, input: [String: Any]) async -> String {
        guard let slackService else {
            return "Error: Slack is not connected."
        }
        return await SlackTools.execute(name: name, input: input, slackService: slackService)
    }

    // MARK: - System Prompt

    private var systemPrompt: String {
        """
        You are Ortus, a helpful AI assistant integrated into a macOS focus mode app. \
        The user is currently in focus mode and cannot access Slack directly. \
        You have tools to search Slack messages, read channel history, list channels, and look up user information. \
        Use these tools to help the user stay informed without breaking their focus.

        Guidelines:
        - Be concise and direct in your responses.
        - When you find messages, summarize them clearly.
        - Resolve user IDs (like U01ABC123) to real names using the get_user_info tool.
        - If the user asks about a channel, first find the channel ID, then read its history.
        - Format your responses for easy scanning.
        """
    }

    enum ClaudeError: LocalizedError {
        case invalidResponse
        case apiError(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "Invalid response from Claude API"
            case .apiError(let code, let body): "Claude API error (\(code)): \(body)"
            }
        }
    }
}
