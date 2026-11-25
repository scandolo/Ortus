import CryptoKit
import Foundation
import OrtusCore

struct InstallerTests {
    static func runAll() throws {
        let checks = InstallerTests()
        checks.readsOnlyAVersionFromLatest()
        checks.readsThisMacsBuildFromTheManifest()
        checks.buildsReleaseURLs()
        try checks.hashesFilesInChunks()
        try checks.signatureMustBeTheNamedTeams()
    }

    func readsOnlyAVersionFromLatest() {
        func version(_ text: String) -> String? { ClaudeRelease.version(from: Data(text.utf8)) }
        expect(version("2.1.331") == "2.1.331")
        expect(version("2.1.331\n") == "2.1.331")
        expect(version(" 2.1.331-beta.1\r\n") == "2.1.331-beta.1")
        for bad in ["", "latest", "2.1", "v2.1.331", "2.1.331/../x", "2.1.331\n2.1.332",
                    "<!DOCTYPE html><html><body>Not available in your region</body></html>",
                    #"<?xml version="1.0"?><Error><Code>NoSuchKey</Code></Error>"#] {
            expect(version(bad) == nil)
        }
        expect(ClaudeRelease.version(from: Data([0xff, 0xfe, 0x32])) == nil)
    }

    func readsThisMacsBuildFromTheManifest() {
        let arm = "4874" + String(repeating: "c", count: 56) + "01f7"
        let intel = String(repeating: "0", count: 64)
        func manifest(armChecksum: String = arm, armSize: String = "381464176") -> Data {
            Data("""
            {"version":"2.1.331","manifestSignatureEnforcement":"flag","commit":"0a1b2c","buildDate":"2026-11-20T10:00:00Z",
             "platforms":{"darwin-arm64":{"binary":"claude","checksum":"\(armChecksum)","size":\(armSize)},
                          "darwin-x64":{"binary":"claude","checksum":"\(intel)","size":397278064},
                          "linux-arm64":{"binary":"claude","checksum":"\(arm)","size":1}},
             "sdkCompat":{"minimum":"1.0.0"}}
            """.utf8)
        }
        expect(ClaudeRelease.build(in: manifest(), platform: "darwin-arm64") == ClaudeRelease.Build(checksum: arm, size: 381464176))
        expect(ClaudeRelease.build(in: manifest(), platform: "darwin-x64") == ClaudeRelease.Build(checksum: intel, size: 397278064))
        expect(ClaudeRelease.build(in: manifest(), platform: "win32-x64") == nil)
        for checksum in [arm.uppercased(), String(arm.dropLast()), arm + "0", String(arm.dropLast()) + "g", ""] {
            expect(ClaudeRelease.build(in: manifest(armChecksum: checksum), platform: "darwin-arm64") == nil)
        }
        for size in ["0", "-5", "\"381464176\"", "null"] {
            expect(ClaudeRelease.build(in: manifest(armSize: size), platform: "darwin-arm64") == nil)
        }
        expect(ClaudeRelease.build(in: Data("<html>502 Bad Gateway</html>".utf8), platform: "darwin-arm64") == nil)
        expect(ClaudeRelease.build(in: Data(#"{"platforms":[]}"#.utf8), platform: "darwin-arm64") == nil)
    }

    func buildsReleaseURLs() {
        let base = "https://downloads.claude.ai/claude-code-releases"
        expect(ClaudeRelease.latestURL.absoluteString == "\(base)/latest")
        expect(ClaudeRelease.manifestURL(version: "2.1.331").absoluteString == "\(base)/2.1.331/manifest.json")
        expect(ClaudeRelease.binaryURL(version: "2.1.331", platform: "darwin-x64").absoluteString == "\(base)/2.1.331/darwin-x64/claude")
        #if arch(arm64)
        expect(ClaudeRelease.currentPlatform == "darwin-arm64")
        #else
        expect(["darwin-arm64", "darwin-x64"].contains(ClaudeRelease.currentPlatform))
        #endif
    }

    func hashesFilesInChunks() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ortus-checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        expect(try ClaudeRelease.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try Data().write(to: file)
        expect(try ClaudeRelease.sha256(of: file) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        // Several reads' worth, ending mid-read.
        let big = Data((0..<(3 << 20) + 7).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try big.write(to: file)
        let expected = SHA256.hash(data: big).map { String(format: "%02x", $0) }.joined()
        expect(try ClaudeRelease.sha256(of: file) == expected)
    }

    func signatureMustBeTheNamedTeams() throws {
        // Anthropic's real binary, when this Mac has it (CI doesn't).
        let claude = URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin/claude")
        if FileManager.default.fileExists(atPath: claude.path) {
            try ClaudeRelease.verifySignature(of: claude, team: ClaudeRelease.anthropicTeam)
            expectRejected { try ClaudeRelease.verifySignature(of: claude, team: ClaudeRelease.openAITeam) }
        }
        let ls = URL(fileURLWithPath: "/bin/ls")
        expectRejected { try ClaudeRelease.verifySignature(of: ls, team: ClaudeRelease.anthropicTeam) }
        // Apple signed /bin/ls, so this would pass if the team were pasted into the requirement as is.
        expectRejected { try ClaudeRelease.verifySignature(of: ls, team: #"ABCDEFGHIJ" or anchor apple or "x"#) }
        let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        expectRejected { try ClaudeRelease.verifySignature(of: me, team: ClaudeRelease.anthropicTeam) }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("ortus-checks-missing-\(UUID().uuidString)")
        expectRejected { try ClaudeRelease.verifySignature(of: missing, team: ClaudeRelease.anthropicTeam) }
    }

    private func expectRejected(_ body: () throws -> Void, file: StaticString = #file, line: UInt = #line) {
        do { try body(); preconditionFailure("Expected the signature check to fail", file: file, line: line) } catch {}
    }
}
