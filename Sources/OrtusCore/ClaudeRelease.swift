import CryptoKit
import Foundation
import Security

/// Where Claude Code's official releases live and how to tell a download is really
/// Anthropic's. Ortus follows the same steps as Anthropic's https://claude.ai/install.sh:
/// read the latest version, read that version's manifest, download the binary for this
/// Mac and check its SHA-256 against the manifest. Ortus also checks the code signature
/// before it runs anything.
public enum ClaudeRelease {
    public static let base = URL(string: "https://downloads.claude.ai/claude-code-releases")!
    public static let latestURL = base.appendingPathComponent("latest")

    public static func manifestURL(version: String) -> URL {
        base.appendingPathComponent(version).appendingPathComponent("manifest.json")
    }

    public static func binaryURL(version: String, platform: String) -> URL {
        base.appendingPathComponent(version).appendingPathComponent(platform).appendingPathComponent("claude")
    }

    /// A trimmed version like 2.1.331 (optionally with a -suffix); nil for anything else
    /// (an HTML error page, an XML "not found"…).
    public static func version(from data: Data) -> String? {
        guard data.count <= 64, let text = String(data: data, encoding: .utf8) else { return nil }
        let version = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$"#
        return version.range(of: pattern, options: .regularExpression) == nil ? nil : version
    }

    public struct Build: Equatable, Sendable {
        public let checksum: String
        public let size: Int64

        public init(checksum: String, size: Int64) {
            self.checksum = checksum
            self.size = size
        }
    }

    /// The platform's checksum (must be 64 lowercase hex) and size, or nil.
    public static func build(in manifest: Data, platform: String) -> Build? {
        guard let json = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              let platforms = json["platforms"] as? [String: Any],
              let entry = platforms[platform] as? [String: Any],
              let checksum = entry["checksum"] as? String, isSHA256(checksum),
              let size = entry["size"] as? Int64, size > 0 else { return nil }
        return Build(checksum: checksum, size: size)
    }

    static func isSHA256(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    /// "darwin-arm64" on Apple silicon (also when an Intel build of Ortus runs under
    /// Rosetta), else "darwin-x64".
    public static var currentPlatform: String {
        #if arch(arm64)
        return "darwin-arm64"
        #else
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let underRosetta = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
        return underRosetta ? "darwin-arm64" : "darwin-x64"
        #endif
    }

    /// Lowercase hex SHA-256 of a file, read a megabyte at a time (the real binary is
    /// about 380 MB).
    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        var finished = false
        while !finished {
            try autoreleasepool {
                let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
                if chunk.isEmpty { finished = true } else { hasher.update(data: chunk) }
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Developer ID teams whose signature Ortus accepts on an agent CLI it installs.
    public static let anthropicTeam = "Q6L2SF6YDW"
    public static let openAITeam = "2DC432GLL2"

    public struct SignatureFailure: Error, Equatable {
        public let status: OSStatus
    }

    /// Throws unless the code at `url` (a symlink counts by its target) is validly signed
    /// through Apple's chain by `team`, checking every architecture.
    public static func verifySignature(of url: URL, team: String) throws {
        // The team is pasted into the requirement, so it may only be a team ID.
        guard team.count == 10, team.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else {
            throw SignatureFailure(status: errSecParam)
        }
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(url.resolvingSymlinksInPath() as CFURL, [], &code)
        guard status == errSecSuccess, let code else { throw SignatureFailure(status: status) }
        var requirement: SecRequirement?
        let text = #"anchor apple generic and certificate leaf[subject.OU] = "\#(team)""#
        status = SecRequirementCreateWithString(text as CFString, [], &requirement)
        guard status == errSecSuccess, let requirement else { throw SignatureFailure(status: status) }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        status = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else { throw SignatureFailure(status: status) }
    }
}
