import Foundation
import OrtusCore

struct UpdateTests {
    func feedOnlyPointsAtOurHosts() {
        func parse(_ json: String) -> UpdateFeed.Entry? { UpdateFeed.parse(Data(json.utf8)) }
        let entry = parse(#"{"version":"1.2.3","zip":"https://ortusmode.com/download/Ortus-macOS.zip"}"#)
        expect(entry?.version == "1.2.3")
        expect(entry?.zip.absoluteString == "https://ortusmode.com/download/Ortus-macOS.zip")
        expect(parse(#"{"version":"v1.2.4","zip":"https://github.com/scandolo/Ortus/releases/latest/download/Ortus-macOS.zip"}"#)?.version == "1.2.4")
        for zip in ["http://ortusmode.com/a.zip", "https://evil.example/a.zip", "https://ortusmode.com.evil.example/a.zip",
                    "https://user@ortusmode.com/a.zip", "file:///tmp/a.zip", "https://raw.githubusercontent.com/a.zip"] {
            expect(parse(#"{"version":"1.2.3","zip":"\#(zip)"}"#) == nil)
        }
        expect(parse(#"{"version":"latest","zip":"https://ortusmode.com/a.zip"}"#) == nil)
        expect(parse(#"{"zip":"https://ortusmode.com/a.zip"}"#) == nil)
        expect(parse("not json") == nil)
    }

    func versionsCompareNumerically() {
        expect(UpdateFeed.isVersion("1.0.10", newerThan: "1.0.9"))
        expect(UpdateFeed.isVersion("1.1", newerThan: "1.0.99"))
        expect(!UpdateFeed.isVersion("1.0.0", newerThan: "1.0"))
        expect(!UpdateFeed.isVersion("1.0.9", newerThan: "1.0.10"))
    }

    /// The checks binary is ad-hoc (linker) signed, like a local build: it must not pass.
    func verifierRejectsCodeThatIsntOurRelease() throws {
        let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        expectFailure { try UpdateVerifier.verify(appAt: me, newerThan: "0") }
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("ortus-checks-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: empty.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        expectFailure { try UpdateVerifier.verify(appAt: empty, newerThan: "0") }
    }

    private func expectFailure(_ body: () throws -> String, file: StaticString = #file, line: UInt = #line) {
        do { _ = try body(); preconditionFailure("Expected verification to fail", file: file, line: line) }
        catch UpdateVerifier.Failure.signature { }
        catch { preconditionFailure("Unexpected error \(error)", file: file, line: line) }
    }
}
