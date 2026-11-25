import Foundation

/// Whether an engine's CLI is signed in, as its own status command reports it.
public enum AgentSignIn: Equatable, Sendable {
    case signedIn(email: String?, plan: String?)
    case signedOut
    /// The CLI didn't answer in a way we understand: shown, never blocks.
    case unknown(String)

    /// Parses `claude auth status --json`: exit 0 and `{"loggedIn":true,…,"subscriptionType":"max","email":…}`
    /// when signed in, exit 1 and `{"loggedIn":false,"authMethod":"none"}` when not.
    /// Anything printed before the JSON (warnings, update notices) is skipped.
    public static func parseClaude(output: String, exitCode: Int32) -> AgentSignIn {
        guard let status = firstJSONObject(in: output), let loggedIn = status["loggedIn"] as? Bool else {
            return .unknown(firstLine(of: output) ?? "No answer (exit code \(exitCode))")
        }
        guard loggedIn else { return .signedOut }
        return .signedIn(email: nonEmpty(status["email"]), plan: nonEmpty(status["subscriptionType"]).map(planName))
    }

    /// Parses `codex login status` (it writes to stderr: pass stdout and stderr together).
    /// Exit 0 with "Logged in using ChatGPT" or "…an API key"; exit 1 with "Not logged in".
    public static func parseCodex(output: String, exitCode: Int32) -> AgentSignIn {
        let text = output.lowercased()
        if exitCode != 0 || text.contains("not logged in") { return .signedOut }
        return .signedIn(email: nil, plan: text.contains("chatgpt") ? "ChatGPT" : nil)
    }

    /// True when the error text from a turn means the user is signed out.
    public static func meansSignedOut(_ text: String) -> Bool {
        let text = text.lowercased()
        let signs = [
            // Claude Code: "Not logged in · Please run /login"
            "not logged in", "please run /login", "invalid api key", "oauth token has expired",
            // Codex
            "codex login", "401 unauthorized", "token_expired", "refresh token",
        ]
        return signs.contains { text.contains($0) }
    }

    /// The sign-in page in a CLI's sign-in output, so the app can offer to open it again.
    /// Local addresses are skipped: Codex first prints the callback server it listens on.
    public static func signInURL(in output: String) -> URL? {
        // Stops at spaces, quotes and the escape that starts a terminal colour code.
        let pattern = try! NSRegularExpression(pattern: #"https?://[^\s<>"'`\x1B]+"#)
        for match in pattern.matches(in: output, range: NSRange(output.startIndex..., in: output)) {
            guard let range = Range(match.range, in: output) else { continue }
            let text = String(output[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
            guard let url = URL(string: text), let host = url.host?.lowercased(),
                  !["localhost", "127.0.0.1", "[::1]", "::1"].contains(host) else { continue }
            return url
        }
        return nil
    }

    // MARK: - Helpers

    /// "max" → "Max plan".
    static func planName(_ subscription: String) -> String {
        let lower = subscription.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst() + " plan"
    }

    /// The first `{…}` in `text` that parses as a JSON object.
    static func firstJSONObject(in text: String) -> [String: Any]? {
        let opens = text.indices.filter { text[$0] == "{" }
        let closes = text.indices.filter { text[$0] == "}" }
        for open in opens {
            for close in closes.reversed() where close > open {
                if let object = try? JSONSerialization.jsonObject(with: Data(text[open...close].utf8)) as? [String: Any] {
                    return object
                }
            }
        }
        return nil
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func firstLine(of output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
            .map { $0.count > 200 ? String($0.prefix(200)) + "…" : $0 }
    }
}
