import Foundation

/// The command-line agents the Agent tab can run.
public enum AgentEngine: String, CaseIterable, Sendable {
    case claudeCode, codex

    public var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    public var binaryName: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        }
    }
}

/// Where a found CLI came from.
public enum AgentSource: String, Equatable, Sendable { case chosen, cli, desktopApp }

/// Where an engine's CLI can be on this Mac.
public enum AgentLocator {
    /// Static CLI paths to probe, most likely first.
    public static func cliCandidates(_ engine: AgentEngine, home: String) -> [String] {
        switch engine {
        case .claudeCode:
            [
                "\(home)/.local/bin/claude",          // native installer
                "/opt/homebrew/bin/claude",           // Homebrew, Apple silicon
                "/usr/local/bin/claude",              // Homebrew, Intel; npm with a system Node
                "\(home)/.claude/local/claude",       // the older local install
                "/run/current-system/sw/bin/claude",  // nix-darwin
            ]
        case .codex:
            ["\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        }
    }

    /// The copy of the CLI bundled inside a desktop app (the Claude app, the ChatGPT or
    /// Codex app), or nil. Only a runnable file counts.
    public static func desktopCopy(_ engine: AgentEngine, home: String, applications: [String] = ["/Applications"], fileManager: FileManager = .default) -> String? {
        switch engine {
        case .claudeCode:
            return claudeAppCopy(home: home, fileManager: fileManager)
        case .codex:
            let inApp = [
                "ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                "ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
                "ChatGPT.app/Contents/Resources/codex",
                "Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                "Codex.app/Contents/Resources/codex",
            ]
            for folder in applications + ["\(home)/Applications"] {
                if let path = inApp.map({ "\(folder)/\($0)" }).first(where: { ClaudeLocation.isRunnable($0, fileManager: fileManager) }) {
                    return path
                }
            }
            return nil
        }
    }

    /// The Claude app keeps one folder per version under `claude-code/`. Today a copy is
    /// at `<version>/<hash>/claude.app/Contents/MacOS/claude`; older apps used
    /// `<version>/claude.app/…` and `<version>/claude`. Newest version first, so a
    /// half-downloaded new version falls back to the one before it.
    private static func claudeAppCopy(home: String, fileManager: FileManager) -> String? {
        let root = "\(home)/Library/Application Support/Claude/claude-code"
        let versions = ((try? fileManager.contentsOfDirectory(atPath: root)) ?? [])
            .filter { !$0.isEmpty && $0.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { Int($0) != nil } }
            .sorted { UpdateFeed.isVersion($0, newerThan: $1) }
        for version in versions {
            let folder = "\(root)/\(version)"
            let hashes = ((try? fileManager.contentsOfDirectory(atPath: folder)) ?? []).sorted()
            let candidates = hashes.map { "\(folder)/\($0)/claude.app/Contents/MacOS/claude" }
                + ["\(folder)/claude.app/Contents/MacOS/claude", "\(folder)/claude"]
            if let path = candidates.first(where: { ClaudeLocation.isRunnable($0, fileManager: fileManager) }) { return path }
        }
        return nil
    }
}
