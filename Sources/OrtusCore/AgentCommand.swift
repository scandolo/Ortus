import Foundation

/// Command lines for running an engine's CLI.
public enum AgentCommand {
    /// The arguments (without the binary) for one Codex turn. Flags go before `resume`,
    /// and the prompt goes last.
    public static func codexTurn(prompt: String, systemPrompt: String, threadID: String?, workingDirectory: String) -> [String] {
        var arguments = [
            "exec", "--json", "--dangerously-bypass-approvals-and-sandbox", "--skip-git-repo-check", "-C", workingDirectory,
            "-c", #"model_reasoning_effort="low""#,
            "-c", "developer_instructions=" + tomlString(systemPrompt),
        ]
        if let threadID { arguments += ["resume", threadID] }
        // "- list my emails" would read as a flag: end the options first.
        if prompt.hasPrefix("-") { arguments.append("--") }
        arguments.append(prompt)
        return arguments
    }

    /// A TOML basic string, for `-c key=value` (Codex reads the value as TOML).
    public static func tomlString(_ value: String) -> String {
        var quoted = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": quoted += #"\\"#
            case "\"": quoted += #"\""#
            case "\n": quoted += #"\n"#
            case "\t": quoted += #"\t"#
            case "\r": quoted += #"\r"#
            case "\u{08}": quoted += #"\b"#
            case "\u{0C}": quoted += #"\f"#
            case _ where scalar.value < 0x20 || scalar.value == 0x7F: quoted += String(format: #"\u%04X"#, scalar.value)
            default: quoted.unicodeScalars.append(scalar)
            }
        }
        return quoted + "\""
    }
}
