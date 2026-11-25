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

    /// Runs the real swap script on temporary folders. A swap that can't finish (a non-admin
    /// account can't touch /Applications) must leave the old app whole and reopen it,
    /// never empty it and nest the new app inside, which macOS then calls damaged.
    func updateNeverLeavesABrokenApp() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("OrtusUpdateChecks-\(UUID().uuidString)", isDirectory: true)
        var locked: [URL] = []
        defer {
            for url in locked { try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
            try? files.removeItem(at: root)
        }
        func makeApp(_ app: URL, version: String) throws {
            try files.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            try Data(version.utf8).write(to: app.appendingPathComponent("Contents/version"))
        }
        func version(_ app: URL) -> String? { try? String(contentsOf: app.appendingPathComponent("Contents/version"), encoding: .utf8) }
        // A process that has already exited, so the script doesn't wait.
        let exited = Process()
        exited.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try exited.run()
        exited.waitUntilExit()
        /// Installs a new app over `target` and returns what the script reopened.
        func update(_ target: URL) throws -> String {
            let work = root.appendingPathComponent("work-\(UUID().uuidString)", isDirectory: true)
            let source = work.appendingPathComponent("unzipped/Ortus.app", isDirectory: true)
            try makeApp(source, version: "new")
            let bash = Process(), output = Pipe()
            bash.executableURL = URL(fileURLWithPath: "/bin/bash")
            bash.arguments = ["-c", UpdateInstaller.script(target: target, source: source, work: work, pid: exited.processIdentifier, relaunch: "/bin/echo")]
            bash.standardOutput = output
            bash.standardError = FileHandle.nullDevice
            try bash.run()
            bash.waitUntilExit()
            expect(!files.fileExists(atPath: work.path))
            return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .newlines)
        }

        let writable = root.appendingPathComponent("Applications/Ortus.app", isDirectory: true)
        try makeApp(writable, version: "old")
        expect(try update(writable) == writable.path)
        expect(version(writable) == "new")
        expect(try files.contentsOfDirectory(atPath: writable.deletingLastPathComponent().path) == ["Ortus.app"])

        let readOnly = root.appendingPathComponent("Locked/Ortus.app", isDirectory: true)
        try makeApp(readOnly, version: "old")
        try files.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.deletingLastPathComponent().path)
        locked.append(readOnly.deletingLastPathComponent())
        expect(!files.isWritableFile(atPath: readOnly.deletingLastPathComponent().path)) // as root nothing is read-only
        expect(try update(readOnly) == readOnly.path)
        expect(version(readOnly) == "old")
        expect(!files.fileExists(atPath: readOnly.appendingPathComponent("Ortus.app").path))
    }

    private func expectFailure(_ body: () throws -> String, file: StaticString = #file, line: UInt = #line) {
        do { _ = try body(); preconditionFailure("Expected verification to fail", file: file, line: line) }
        catch UpdateVerifier.Failure.signature { }
        catch { preconditionFailure("Unexpected error \(error)", file: file, line: line) }
    }
}
