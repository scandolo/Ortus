import Foundation
import OrtusCore

/// Installs the agent CLI without Terminal: Claude Code, or Codex for the experimental
/// Codex mode. Everything it downloads goes into its own folder in Ortus's Caches, which is
/// deleted when the install finishes, fails or is cancelled.
///
/// Claude Code: Ortus does the steps of Anthropic's install script (https://claude.ai/install.sh)
/// itself, so it can show real progress and check the binary before anything runs. It reads
/// the latest version and its manifest, downloads the binary for this Mac, checks its size,
/// SHA-256 and Anthropic's Developer ID signature, then runs the binary's own `install`,
/// which puts `claude` in ~/.local/bin.
///
/// Codex: OpenAI's script does much more (locking, conflict checks, the marker `codex update`
/// relies on), so Ortus runs that script with prompts turned off, then checks the installed
/// binary is signed by OpenAI.
@MainActor
final class AgentInstaller: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// `total` is 0 when the size isn't known (Codex).
        case downloading(received: Int64, total: Int64)
        /// The UI says "Checking it’s from Anthropic" (or OpenAI).
        case checking
        case settingUp
        /// The installed CLI, e.g. /Users/x/.local/bin/claude.
        case done(path: String)
        /// `message` is one plain sentence for users; `details` is the raw output.
        case failed(message: String, details: String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var engine: AgentEngine?

    var isRunning: Bool {
        switch phase {
        case .downloading, .checking, .settingUp: return true
        case .idle, .done, .failed: return false
        }
    }

    private var job: Task<Void, Never>?
    /// This install's own folder. It also tells a late progress update which install it's from.
    private var folder: URL?

    nonisolated static var cacheRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ortusmode.preview", isDirectory: true)
            .appendingPathComponent("agent-install", isDirectory: true)
    }

    nonisolated private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }
    nonisolated private static let codexScriptURL = URL(string: "https://chatgpt.com/codex/install.sh")!
    /// chatgpt.com redirects to releases.openai.com; the script must come from one of them.
    nonisolated private static let codexScriptHosts: Set<String> = ["chatgpt.com", "releases.openai.com"]

    /// The official one-line command, for "Install in Terminal instead".
    nonisolated static func terminalCommand(for engine: AgentEngine) -> String {
        switch engine {
        case .claudeCode: return "curl -fsSL https://claude.ai/install.sh | bash"
        case .codex: return "curl -fsSL https://chatgpt.com/codex/install.sh | sh"
        }
    }

    func install(_ engine: AgentEngine) {
        guard !isRunning else { return }
        // Whatever an earlier install left behind (Ortus quit mid-download) goes first.
        try? FileManager.default.removeItem(at: Self.cacheRoot)
        let folder = Self.cacheRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.folder = folder
        self.engine = engine
        phase = .downloading(received: 0, total: 0)
        job = Task {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let path: String
                switch engine {
                case .claudeCode: path = try await installClaudeCode(in: folder)
                case .codex: path = try await installCodex(in: folder)
                }
                if !Task.isCancelled { phase = .done(path: path) }
            } catch {
                if !Task.isCancelled {
                    let failure = Self.failure(error, engine: engine)
                    phase = .failed(message: failure.message, details: failure.details)
                }
            }
            try? FileManager.default.removeItem(at: folder)
            if self.folder == folder {
                self.folder = nil
                job = nil
            }
        }
    }

    /// Stop the download or the setup command and delete everything downloaded.
    func cancel() {
        job?.cancel()
        job = nil
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        engine = nil
        phase = .idle
    }

    #if DEBUG
    /// Snapshot harness: show a step without running anything.
    func pinForSnapshot(_ pinned: Phase) {
        phase = pinned
        engine = pinned == .idle ? nil : engine
    }
    #endif

    // MARK: - Claude Code

    private func installClaudeCode(in folder: URL) async throws -> String {
        let session = installerSession()
        defer { session.finishTasksAndInvalidate() }
        let (latest, _) = try await Self.fetch(ClaudeRelease.latestURL, with: session)
        guard let version = ClaudeRelease.version(from: latest) else {
            throw InstallProblem.badAnswer("\(ClaudeRelease.latestURL.absoluteString) didn’t return a version:\n\(String(decoding: latest.prefix(300), as: UTF8.self))")
        }
        let platform = ClaudeRelease.currentPlatform
        let (manifest, _) = try await Self.fetch(ClaudeRelease.manifestURL(version: version), with: session)
        guard let build = ClaudeRelease.build(in: manifest, platform: platform) else {
            throw InstallProblem.badAnswer("The manifest for Claude Code \(version) has no valid \(platform) build.")
        }
        // The download and the copy `install` makes of it are on disk together for a moment.
        let needed = build.size * 2
        if let free = Self.freeSpace(at: folder), free < needed {
            throw InstallProblem.noSpace(needed: needed, free: free)
        }

        let total = build.size
        phase = .downloading(received: 0, total: total)
        let binary = folder.appendingPathComponent("claude-\(version)-\(platform)")
        let download = FileDownload(to: binary) { [weak self] received in
            Task { @MainActor in self?.downloaded(received, of: total, into: folder) }
        }
        try await download.run(ClaudeRelease.binaryURL(version: version, platform: platform))
        try Task.checkCancellation()

        phase = .checking
        try await Task.detached(priority: .userInitiated) { try Self.check(binary, against: build) }.value
        try Task.checkCancellation()

        phase = .settingUp
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let setup = try await Self.run(binary, ["install"], in: folder, timeout: .seconds(180))
        try? FileManager.default.removeItem(at: binary)
        guard setup.succeeded else { throw InstallProblem.setup(setup.details) }

        let path = Self.home + "/.local/bin/claude"
        guard ClaudeLocation.isRunnable(path) else {
            throw InstallProblem.setup("Setup ended but \(path) isn’t there.\n\n\(setup.output)")
        }
        try await Self.confirmVersion(of: path, in: folder)
        return path
    }

    private func downloaded(_ received: Int64, of total: Int64, into folder: URL) {
        guard self.folder == folder, case .downloading = phase else { return }
        phase = .downloading(received: received, total: total)
    }

    /// Size, SHA-256 and signature, before anything runs. Anything off deletes the file.
    nonisolated private static func check(_ binary: URL, against build: ClaudeRelease.Build) throws {
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: binary.path)[.size] as? NSNumber)?.int64Value
            guard size == build.size else {
                throw InstallProblem.mismatch("Downloaded \(size ?? 0) bytes; the manifest says \(build.size).")
            }
            let checksum = try ClaudeRelease.sha256(of: binary)
            guard checksum == build.checksum else {
                throw InstallProblem.mismatch("SHA-256 is \(checksum); the manifest says \(build.checksum).")
            }
            do {
                try ClaudeRelease.verifySignature(of: binary, team: ClaudeRelease.anthropicTeam)
            } catch {
                throw InstallProblem.mismatch("It isn’t signed by Anthropic’s Developer ID (\(error)).")
            }
        } catch {
            try? FileManager.default.removeItem(at: binary)
            throw error
        }
    }

    // MARK: - Codex

    private func installCodex(in folder: URL) async throws -> String {
        let session = installerSession()
        defer { session.finishTasksAndInvalidate() }
        let (script, origin) = try await Self.fetch(Self.codexScriptURL, with: session)
        guard origin?.scheme == "https", let host = origin?.host?.lowercased(), Self.codexScriptHosts.contains(host) else {
            throw InstallProblem.badAnswer("The Codex install script came from \(origin?.absoluteString ?? "an unknown address").")
        }
        guard script.starts(with: Data("#!".utf8)) else {
            throw InstallProblem.badAnswer("\(origin?.absoluteString ?? "The Codex install script") isn’t a shell script:\n\(String(decoding: script.prefix(300), as: UTF8.self))")
        }
        let scriptFile = folder.appendingPathComponent("install.sh")
        try script.write(to: scriptFile)
        try Task.checkCancellation()

        phase = .settingUp
        // CODEX_NON_INTERACTIVE answers "no" to every prompt: it won't remove another Codex or launch this one.
        let setup = try await Self.run(URL(fileURLWithPath: "/bin/sh"), [scriptFile.path], in: folder,
                                       extraEnvironment: ["CODEX_NON_INTERACTIVE": "1"], timeout: .seconds(300))
        try? FileManager.default.removeItem(at: scriptFile)
        guard setup.succeeded else { throw InstallProblem.setup(setup.details) }

        phase = .checking
        let path = Self.home + "/.local/bin/codex"
        guard ClaudeLocation.isRunnable(path) else {
            throw InstallProblem.setup("Setup ended but \(path) isn’t there.\n\n\(setup.output)")
        }
        // ~/.local/bin/codex links into ~/.codex/packages/standalone/releases/<version>/.
        let binary = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        do {
            try await Task.detached(priority: .userInitiated) {
                try ClaudeRelease.verifySignature(of: binary, team: ClaudeRelease.openAITeam)
            }.value
        } catch {
            throw InstallProblem.notFromOpenAI("\(binary.path) isn’t signed by OpenAI’s Developer ID (\(error)).")
        }
        try Task.checkCancellation()
        try await Self.confirmVersion(of: path, in: folder)
        return path
    }

    // MARK: - Helpers

    /// GET `url`. Anything but a 200 is a bad answer. Also returns where the answer came
    /// from after redirects.
    nonisolated private static func fetch(_ url: URL, with session: URLSession) async throws -> (Data, URL?) {
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw InstallProblem.badAnswer("\(url.absoluteString) answered HTTP \(status).") }
        return (data, response.url)
    }

    nonisolated private static func freeSpace(at folder: URL) -> Int64? {
        try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }

    nonisolated private static func confirmVersion(of path: String, in folder: URL) async throws {
        let check = try await run(URL(fileURLWithPath: path), ["--version"], in: folder, timeout: .seconds(30))
        guard check.succeeded else { throw InstallProblem.setup("\(path) --version didn’t work. \(check.details)") }
    }

    /// The installers get a small, known environment rather than Ortus's own.
    nonisolated private static func environment(extra: [String: String]) -> [String: String] {
        var environment = [
            "HOME": home,
            "USER": NSUserName(),
            "LANG": "en_US.UTF-8",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            // Codex's script picks the profile it adds ~/.local/bin to from SHELL. Without
            // it, it writes ~/.profile, which zsh never reads.
            "SHELL": ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        ]
        environment.merge(extra) { $1 }
        return environment
    }

    /// Run one command and wait for it. It's stopped, with anything it started, after
    /// `timeout` or when the install is cancelled. Output goes to a file rather than a pipe,
    /// so a helper the installer leaves running can't keep Ortus waiting.
    nonisolated private static func run(_ executable: URL, _ arguments: [String], in folder: URL,
                                        extraEnvironment: [String: String] = [:],
                                        timeout: Duration) async throws -> CommandResult {
        let log = folder.appendingPathComponent("output-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: log.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: log.path])
        }
        defer { try? FileManager.default.removeItem(at: log) }
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = folder
        process.environment = environment(extra: extraEnvironment)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output

        let control = CommandControl()
        let timer = Task.detached {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { control.stop(timedOut: true) }
        }
        defer { timer.cancel() }
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { ended in
                    control.exited()
                    continuation.resume(returning: ended.terminationStatus)
                }
                do {
                    try process.run()
                    control.started(process.processIdentifier)
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            control.stop(timedOut: false)
        }
        let printed = (try? Data(contentsOf: log)) ?? Data()
        return CommandResult(status: status, timedOut: control.timedOut,
                             output: String(decoding: printed.suffix(16_000), as: UTF8.self))
    }

    /// One plain sentence for users, and the details behind it.
    nonisolated private static func failure(_ error: Error, engine: AgentEngine) -> (message: String, details: String) {
        let product = engine == .claudeCode ? "Claude Code" : "Codex"
        let maker = engine == .claudeCode ? "Anthropic" : "OpenAI"
        let unreachable = "Ortus couldn’t reach \(maker). Check your connection and try again."
        let serverDown = "\(maker)’s download server didn’t answer. Try again in a minute."
        let noRoom = "There isn’t enough free space for \(product)"
        let setupFailed = "\(product)’s setup didn’t finish. Try again, or install it in Terminal."
        let offline: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                                        .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed]
        switch error {
        case let problem as InstallProblem:
            switch problem {
            case .badAnswer(let details):
                return (serverDown, details)
            case .mismatch(let details):
                return ("The download didn’t match \(maker)’s release, so Ortus deleted it. Try again.", details)
            case .noSpace(let needed, let free):
                return ("\(noRoom) (about \(megabytes(needed)) MB).",
                        "\(free / 1_000_000) MB free. The download and the installed copy need about \(megabytes(needed)) MB together.")
            case .setup(let details) where details.contains("No space left on device"):
                return ("\(noRoom).", details)
            case .setup(let details):
                return (setupFailed, details)
            case .notFromOpenAI(let details):
                return ("Codex installed, but Ortus couldn’t confirm it’s from OpenAI. Install it in Terminal instead.", details)
            }
        case let error where isOutOfSpace(error):
            return ("\(noRoom).", error.localizedDescription)
        case let error as URLError where offline.contains(error.code):
            return (unreachable, "\(error.failingURL?.absoluteString ?? ""): \(error.localizedDescription)")
        case let error as URLError:
            return (serverDown, "\(error.failingURL?.absoluteString ?? ""): \(error.localizedDescription)")
        default:
            return (setupFailed, "\(error)")
        }
    }

    /// Rounded up to the next 100 MB, the way Finder counts (1 MB = 1,000,000 bytes).
    nonisolated private static func megabytes(_ bytes: Int64) -> Int64 {
        (bytes + 99_999_999) / 100_000_000 * 100
    }

    nonisolated private static func isOutOfSpace(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteOutOfSpaceError { return true }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOSPC) { return true }
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error else { return false }
        return isOutOfSpace(underlying)
    }
}

/// What went wrong, before it's put into words for users.
private enum InstallProblem: Error {
    /// The download server answered with something unexpected.
    case badAnswer(String)
    /// The download's size, checksum or signature is off.
    case mismatch(String)
    case noSpace(needed: Int64, free: Int64)
    /// The installer or the installed CLI failed or timed out.
    case setup(String)
    /// Codex's script finished but the binary isn't signed by OpenAI.
    case notFromOpenAI(String)
}

/// How an installer command ended and the end of what it printed.
private struct CommandResult {
    let status: Int32
    let timedOut: Bool
    let output: String

    var succeeded: Bool { status == 0 && !timedOut }

    var details: String {
        let ending = timedOut ? "It was stopped after running too long." : "It ended with status \(status)."
        return output.isEmpty ? ending : "\(ending)\n\n\(output)"
    }
}

/// No cache, and give up on a server that goes quiet for 30 seconds.
private func installerSession(delegate: URLSessionDelegate? = nil) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
}

/// Downloads one file with byte progress, at most four updates a second. URLSession calls
/// it on the session's own serial queue, so only `continuation` needs the lock.
private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var lastReport = Date.distantPast
    private var problem: Error?

    init(to destination: URL, progress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    /// Download `url` to the destination. Cancelling the calling task stops it.
    func run(_ url: URL) async throws {
        let session = installerSession(delegate: self)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock { self.continuation = continuation }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date()
        guard now.timeIntervalSince(lastReport) >= 0.25 else { return }
        lastReport = now
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // URLSession deletes `location` once this returns, so move it into place now.
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let url = downloadTask.originalRequest?.url?.absoluteString ?? "The download"
            problem = InstallProblem.badAnswer("\(url) answered HTTP \(status).")
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            problem = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        if let failure = error ?? problem {
            continuation?.resume(throwing: failure)
        } else {
            continuation?.resume()
        }
    }
}

/// Stops an installer command on timeout or cancel; shared by the timer, the cancel handler
/// and the exit handler. Process starts each command in its own process group, so the
/// signal goes to the whole group and whatever the command started stops too.
private final class CommandControl: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var hasExited = false
    private var stopRequested = false
    private var didTimeOut = false

    var timedOut: Bool { lock.withLock { didTimeOut } }

    func started(_ pid: pid_t) {
        let stop = lock.withLock { () -> Bool in
            self.pid = pid
            return stopRequested
        }
        if stop { terminate() }
    }

    func stop(timedOut: Bool) {
        lock.withLock {
            if timedOut, !hasExited { didTimeOut = true }
            stopRequested = true
        }
        terminate()
    }

    func exited() {
        lock.withLock { hasExited = true }
    }

    /// SIGTERM now, SIGKILL if it's still running 5 seconds later.
    private func terminate() {
        send(SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { self.send(SIGKILL) }
    }

    private func send(_ signal: Int32) {
        lock.withLock {
            guard pid > 0, !hasExited else { return }
            kill(-pid, signal)
            kill(pid, signal)
        }
    }
}
