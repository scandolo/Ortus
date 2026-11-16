import Foundation
import AppKit
import Combine
import OrtusCore

/// Lightweight in-app updater. Reads the feed on ortusmode.com (`UpdateFeed`),
/// and if it names a newer version, downloads that zip, checks the new bundle is
/// signed with our Developer ID and is newer than the running build
/// (`UpdateVerifier`), then swaps the app bundle in place via a small detached
/// helper script and relaunches.
///
/// Releases are Developer ID signed and notarized, so the code signature is the
/// update signature: a download that isn't ours is deleted, never installed.
/// The feed lives on our domain (it redirects to the GitHub release today), so
/// where releases are hosted can change without shipping a new app.
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
    /// The user asked to update during a focus session; it installs once focus is over.
    @Published private(set) var installsAfterFocus = false
    private var focusEndWatch: AnyCancellable?
    /// How long to stay out of focus before a scheduled update restarts Ortus, so a
    /// user who starts another session right away isn't interrupted.
    static let delayAfterFocus: TimeInterval = 60 * 60
    /// Opening the panel also checks; this catches releases while it stays closed.
    static let checkInterval: TimeInterval = 60 * 60
    nonisolated static let notificationID = "update-available"
    private var checkTimer: Timer?
    private var notifyWatch: AnyCancellable?

    /// Where the latest version's zip is, from the last check.
    private var latestZip: URL?
    nonisolated static let unverifiedMessage = "The update couldn't be verified, so it wasn't installed."

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    #if DEBUG
    private var pinnedForSnapshot = false
    /// The snapshot harness shows a fixed state; checks leave it alone.
    func pinForSnapshot(_ state: UpdateState) {
        self.state = state
        pinnedForSnapshot = true
    }
    #endif

    var availableVersion: String? {
        if case let .available(version) = state { return version }
        return nil
    }

    // MARK: - Check

    /// Query the latest published release and compare it to the running build.
    /// Network hiccups stay silent (back to `.idle`) so a flaky connection never
    /// nags the user — we just try again on the next launch.
    func checkForUpdates() async {
        guard Bundle.main.object(forInfoDictionaryKey: "OrtusPreviewBuild") as? Bool != true else { return }
        if case .downloading = state { return }
        if case .checking = state { return }
        #if DEBUG
        if pinnedForSnapshot { return }
        #endif
        // Keep "You're on the latest version" on screen while checking again.
        if state != .upToDate { state = .checking }
        do {
            let request = URLRequest(url: UpdateFeed.url, cachePolicy: .reloadIgnoringLocalCacheData)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let entry = UpdateFeed.parse(data) else {
                state = .idle
                return
            }
            let latest = entry.version
            if UpdateFeed.isVersion(latest, newerThan: currentVersion) {
                latestZip = entry.zip
                state = .available(version: latest)
                Analytics.capture("update_available", ["from": currentVersion, "to": latest])
            } else {
                state = .upToDate
            }
        } catch {
            state = .idle
        }
    }

    /// Check every `checkInterval` and send one notification per new version, held
    /// until focus is over. Skipped once the user chose "Update after session".
    func startBackgroundChecks(_ focusManager: FocusManager) {
        guard checkTimer == nil else { return }
        notifyWatch = $state.combineLatest(focusManager.$isInFocus.removeDuplicates())
            .sink { [weak self, weak focusManager] state, inFocus in
                guard let self, let focusManager, case let .available(version) = state,
                      !inFocus, !self.installsAfterFocus else { return }
                let key = "notifiedUpdateVersion"
                guard UserDefaults.standard.string(forKey: key) != version else { return }
                UserDefaults.standard.set(version, forKey: key)
                focusManager.sendNotification(title: "Ortus \(version) is ready",
                                              body: "Open Settings to restart and update.",
                                              identifier: Self.notificationID)
            }
        checkTimer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkForUpdates() }
        }
        Task { await checkForUpdates() }
    }

    // MARK: - Install

    /// Download the latest release and hand off to a detached helper that swaps
    /// the bundle once we quit. Must not run during a focus session — quitting is
    /// trapped then, and the helper would wait forever for us to exit.
    func downloadAndInstall(isInFocus: Bool) async {
        guard Bundle.main.object(forInfoDictionaryKey: "OrtusPreviewBuild") as? Bool != true else { return }
        guard case .available = state, let zip = latestZip else { return }
        guard !isInFocus else {
            state = .failed("Finish your focus session before updating.")
            return
        }
        installsAfterFocus = false
        focusEndWatch = nil
        state = .downloading
        Analytics.capture("update_install_started", ["to": availableVersion ?? "unknown"])
        let bundlePath = Bundle.main.bundlePath
        let running = currentVersion
        do {
            let download = try await Task.detached(priority: .userInitiated) {
                try Self.fetchExtractAndVerify(zip: zip, newerThan: running)
            }.value
            try launchUpdaterAndQuit(download, targetBundle: bundlePath)
        } catch UpdateError.unverified {
            state = .failed(UpdateError.unverified.localizedDescription)
            Analytics.capture("update_verification_failed", ["to": availableVersion ?? "unknown"])
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Quitting is blocked during focus, so update once Ortus has been out of focus
    /// for `delayAfterFocus`. Starting another session in that window restarts the wait.
    func installAfterFocus(_ focusManager: FocusManager) {
        guard case .available = state, !installsAfterFocus else { return }
        installsAfterFocus = true
        Analytics.capture("update_scheduled_after_focus", ["to": availableVersion ?? "unknown"])
        focusEndWatch = focusManager.$isInFocus
            .removeDuplicates()
            .map { inFocus -> AnyPublisher<Void, Never> in
                inFocus ? Empty().eraseToAnyPublisher()
                    : Just(()).delay(for: .seconds(Self.delayAfterFocus), scheduler: RunLoop.main).eraseToAnyPublisher()
            }
            .switchToLatest()
            .first()
            .sink { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.installsAfterFocus = false
                    self.focusEndWatch = nil
                    await self.downloadAndInstall(isInFocus: focusManager.isInFocus)
                }
            }
    }

    // MARK: - Helpers

    private enum UpdateError: LocalizedError {
        case extractFailed, appNotFound, unverified
        var errorDescription: String? {
            switch self {
            case .unverified: return UpdateService.unverifiedMessage
            case .extractFailed: return "Couldn't unpack the update."
            case .appNotFound: return "The downloaded update didn't contain Ortus.app."
            }
        }
    }

    /// The extracted, verified app and the temp folder holding the whole download.
    private struct Download: Sendable {
        let app: URL
        let folder: URL
    }

    /// Download the release zip, extract it into a temp dir and verify the app
    /// inside. Runs off the main thread (synchronous network + disk) so the UI
    /// stays responsive. Any failure deletes the download.
    nonisolated private static func fetchExtractAndVerify(zip url: URL, newerThan running: String) throws -> Download {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ortus-update-\(UUID().uuidString)")
        do {
            let data = try Data(contentsOf: url)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let app = try extract(data, into: tmpDir)
            do {
                try UpdateVerifier.verify(appAt: app, newerThan: running)
            } catch {
                throw UpdateError.unverified
            }
            return Download(app: app, folder: tmpDir)
        } catch {
            try? FileManager.default.removeItem(at: tmpDir)
            throw error
        }
    }

    nonisolated private static func extract(_ data: Data, into tmpDir: URL) throws -> URL {
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
    private func launchUpdaterAndQuit(_ download: Download, targetBundle: String) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        TARGET="\(targetBundle)"
        SRC="\(download.app.path)"
        WORK="\(download.folder.path)"
        for _ in $(seq 1 300); do
            kill -0 \(pid) 2>/dev/null || break
            sleep 0.2
        done
        # If Ortus is still running, the quit was blocked — abort without touching it.
        if kill -0 \(pid) 2>/dev/null; then
            rm -rf "$WORK"
            exit 0
        fi
        rm -rf "$TARGET"
        mv "$SRC" "$TARGET"
        xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
        open "$TARGET"
        rm -rf "$WORK"
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
}
