import Foundation
import AppKit

/// Lightweight in-app updater. Mirrors the `install.sh` flow: ask the GitHub
/// releases API for the latest version, and if it's newer than the running
/// build, download the release zip, swap the app bundle in place via a small
/// detached helper script, and relaunch.
///
/// Ortus isn't notarized and ships via `curl | bash`, so there's no Sparkle/
/// appcast infrastructure to lean on — this stays deliberately small and uses
/// the same GitHub release artifact the installer already consumes. (A future
/// move to Sparkle would add cryptographic update signing, which this lacks; we
/// trust the HTTPS GitHub release, the same trust model as the installer.)
@MainActor
final class UpdateService: ObservableObject {
    enum UpdateState: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading
        case failed(String)
    }

    @Published private(set) var state: UpdateState = .idle

    static let repo = "scandolo/Ortus"
    private static let apiURL = "https://api.github.com/repos/\(repo)/releases/latest"
    private static let zipURL = "https://github.com/\(repo)/releases/latest/download/Ortus-macOS.zip"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var availableVersion: String? {
        if case let .available(version) = state { return version }
        return nil
    }

    // MARK: - Check

    /// Query the latest published release and compare it to the running build.
    /// Network hiccups stay silent (back to `.idle`) so a flaky connection never
    /// nags the user — we just try again on the next launch.
    func checkForUpdates() async {
        if case .downloading = state { return }
        if case .checking = state { return }
        state = .checking
        do {
            var request = URLRequest(url: URL(string: Self.apiURL)!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                state = .idle
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            if Self.isVersion(latest, newerThan: currentVersion) {
                state = .available(version: latest)
                Analytics.capture("update_available", ["from": currentVersion, "to": latest])
            } else {
                state = .upToDate
            }
        } catch {
            state = .idle
        }
    }

    // MARK: - Install

    /// Download the latest release and hand off to a detached helper that swaps
    /// the bundle once we quit. Must not run during a focus session — quitting is
    /// trapped then, and the helper would wait forever for us to exit.
    func downloadAndInstall(isInFocus: Bool) async {
        guard case .available = state else { return }
        guard !isInFocus else {
            state = .failed("Finish your focus session before updating.")
            return
        }
        state = .downloading
        Analytics.capture("update_install_started", ["to": availableVersion ?? "unknown"])
        let zip = Self.zipURL
        let bundlePath = Bundle.main.bundlePath
        do {
            let newApp = try await Task.detached(priority: .userInitiated) {
                try Self.fetchAndExtract(zipURLString: zip)
            }.value
            try launchUpdaterAndQuit(newApp: newApp, targetBundle: bundlePath)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private enum UpdateError: LocalizedError {
        case badURL, extractFailed, appNotFound
        var errorDescription: String? {
            switch self {
            case .badURL: return "Couldn't build the download URL."
            case .extractFailed: return "Couldn't unpack the update."
            case .appNotFound: return "The downloaded update didn't contain Ortus.app."
            }
        }
    }

    /// Download the release zip and extract it into a temp dir. Runs off the main
    /// thread (synchronous network + disk) so the UI stays responsive.
    nonisolated private static func fetchAndExtract(zipURLString: String) throws -> URL {
        guard let url = URL(string: zipURLString) else { throw UpdateError.badURL }
        let data = try Data(contentsOf: url)

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ortus-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let zipPath = tmpDir.appendingPathComponent("Ortus-macOS.zip")
        try data.write(to: zipPath)

        let unzipped = tmpDir.appendingPathComponent("unzipped")
        try FileManager.default.createDirectory(at: unzipped, withIntermediateDirectories: true)

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipPath.path, unzipped.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw UpdateError.extractFailed }

        let direct = unzipped.appendingPathComponent("Ortus.app")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        // Some zips nest the app one level down — search a single level deep.
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: unzipped, includingPropertiesForKeys: nil) {
            for entry in entries {
                let candidate = entry.appendingPathComponent("Ortus.app")
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        throw UpdateError.appNotFound
    }

    /// Write a helper script that waits for us to exit, swaps the bundle, and
    /// relaunches — then spawn it detached and quit. The script self-aborts if we
    /// don't exit within ~60s (e.g. a focus session traps the quit) so it can't
    /// hang around or swap the bundle out from under a still-running app.
    private func launchUpdaterAndQuit(newApp: URL, targetBundle: String) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        TARGET="\(targetBundle)"
        SRC="\(newApp.path)"
        for _ in $(seq 1 300); do
            kill -0 \(pid) 2>/dev/null || break
            sleep 0.2
        done
        # If Ortus is still running, the quit was blocked — abort without touching it.
        if kill -0 \(pid) 2>/dev/null; then
            rm -rf "$(dirname "$SRC")"
            exit 0
        fi
        rm -rf "$TARGET"
        mv "$SRC" "$TARGET"
        xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
        open "$TARGET"
        rm -rf "$(dirname "$SRC")"
        """
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ortus-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let runner = Process()
        runner.executableURL = URL(fileURLWithPath: "/bin/bash")
        runner.arguments = [scriptURL.path]
        try runner.run()

        NSApplication.shared.terminate(nil)
    }

    /// Compare dot-separated version strings numerically (e.g. "1.0.10" > "1.0.9").
    nonisolated static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
