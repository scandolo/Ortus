import Combine
import Foundation
import OrtusCore
import SwiftUI

/// Drives the in-app chat by spawning the user's locally-installed agent CLI as a
/// subprocess, streaming its JSON events back into the chat view. Claude Code for
/// everyone; Codex when the user turns it on under Settings › Experimental. Uses the
/// user's own sign-in and connectors: Ortus doesn't need an API key of its own.
@MainActor
final class ClaudeCodeService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draftText = ""
    @Published var isProcessing = false
    @Published var error: String?
    @Published private(set) var errorDetails: String?
    @Published private(set) var failedPrompt: String?

    @AppStorage("claudeBinaryPath") var claudeBinaryPath = ""
    @AppStorage("codexBinaryPath") var codexBinaryPath = ""

    /// Which CLI runs the agent. Switching starts a new conversation: Claude Code and
    /// Codex can't share one.
    @Published var engine = AgentEngine(rawValue: UserDefaults.standard.string(forKey: "agentEngine") ?? "") ?? .claudeCode {
        didSet {
            guard engine != oldValue else { return }
            UserDefaults.standard.set(engine.rawValue, forKey: "agentEngine")
            engineDidChange()
        }
    }

    /// The file the user picked with "Find it", for the current engine.
    var chosenPath: String {
        get { engine == .codex ? codexBinaryPath : claudeBinaryPath }
        set { if engine == .codex { codexBinaryPath = newValue } else { claudeBinaryPath = newValue } }
    }

    /// The one-click install. Owned here so it carries on when the popup closes.
    let installer = AgentInstaller()
    private var installWatch: AnyCancellable?

    /// What the CLI says about the user's account. nil until the first check.
    @Published private(set) var signIn: AgentSignIn?
    @Published private(set) var isCheckingSignIn = false
    /// A sign-in runs in the browser; Ortus waits for the CLI to say it's done.
    @Published private(set) var isWaitingForSignIn = false
    @Published private(set) var signInPageURL: URL?
    @Published private(set) var signInError: String?
    private var signInProcess: Process?
    private var signInInput: FileHandle?
    private var signInPoll: Task<Void, Never>?
    private var signInOutput = ""
    /// Codex picks its own session id; kept to resume the conversation.
    private var codexThreadID: String?

    /// The user's focus right now, in one sentence for the system prompt. Set by the
    /// app once FocusManager exists; read again on every message.
    var focusContext: () -> String? = { nil }

    /// The text sent from each draft card, which then shows it read-only.
    @Published var sentDrafts: [String: String] = [:]

    @Published private(set) var canUndoClear = false
    private var clearedConversation: (messages: [ChatMessage], sessionID: String, started: Bool)?
    private var sessionID = UUID().uuidString
    private var hasStartedSession = false
    private var currentProcess: Process?
    private var currentTask: Task<Void, Never>?
    /// The answer being streamed, and the chat rows that show it.
    private var turn: ChatTurn?
    private var activityID: UUID?
    private var answerID: UUID?

    /// The CLI resolved from the user's login-shell PATH. Filled in asynchronously
    /// by `detectIfNeeded()` so we catch installs the static list misses
    /// (nvm/fnm/asdf, custom npm prefixes, anything on the user's PATH). Published so
    /// the chat/settings UI unlocks the moment detection succeeds.
    @Published private var shellResolvedPath: String?
    /// The copy inside the Claude app (or the ChatGPT app, for Codex): used when there's
    /// no CLI of its own. It reads the same sign-in as the CLI.
    @Published private var desktopCopyPath: String?
    /// True while the login-shell probe runs, so the UI can wait for the answer.
    @Published private(set) var isDetecting = false
    private var hasRunDetection = false

    /// Where Ortus finds the agent, in order: the file the user chose, the CLI's usual
    /// install places, the CLI on the Terminal's PATH, then the desktop app's copy.
    var resolvedBinaryPath: String? {
        if !chosenPath.isEmpty, ClaudeLocation.isRunnable(chosenPath) { return chosenPath }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if let cli = AgentLocator.cliCandidates(engine, home: home).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return cli
        }
        return shellResolvedPath ?? desktopCopyPath
    }

    var binarySource: AgentSource? {
        guard let path = resolvedBinaryPath else { return nil }
        if !chosenPath.isEmpty, path == chosenPath { return .chosen }
        return path == desktopCopyPath ? .desktopApp : .cli
    }

    var isConfigured: Bool {
        #if DEBUG
        if missingForSnapshot { return false }
        #endif
        return resolvedBinaryPath != nil
    }

    /// Found, and the CLI said the user is signed out.
    var isSignedOut: Bool { isConfigured && signIn == .signedOut }

    #if DEBUG
    /// Snapshot harness: show Chat as if Claude Code weren't installed.
    @Published var missingForSnapshot = false
    /// Snapshot harness: a sign-in answer that skips running the CLI.
    private var signInForSnapshot: AgentSignIn?

    func pinForSnapshot(signIn pinned: AgentSignIn?, waiting: Bool) {
        signInForSnapshot = pinned
        signIn = pinned
        isWaitingForSignIn = waiting
        signInPageURL = waiting ? URL(string: "https://claude.ai/oauth/authorize") : nil
    }
    #endif

    init() {
        // A finished install: find the new CLI, then check its sign-in.
        installWatch = installer.$phase.sink { [weak self] phase in
            guard case .done = phase else { return }
            Task { @MainActor in self?.redetect() }
        }
    }

    /// Probe for the CLI once, off the main thread. Static paths are checked first
    /// (synchronous, instant); the shell probe and the desktop app only run when none
    /// of them hit. Then the sign-in check. Safe to call repeatedly — it no-ops after
    /// the first run unless `redetect()` resets it.
    func detectIfNeeded() {
        guard !hasRunDetection else { return }
        hasRunDetection = true
        // A static path (or user override) already resolves — no need to spawn a shell.
        if resolvedBinaryPath != nil {
            refreshSignIn()
            return
        }
        isDetecting = true
        let engine = self.engine
        Task.detached(priority: .utility) {
            let path = Self.resolveViaLoginShell(engine.binaryName)
            let desktop = path == nil ? AgentLocator.desktopCopy(engine, home: NSHomeDirectory()) : nil
            await MainActor.run {
                guard self.engine == engine else { return }
                self.shellResolvedPath = path
                self.desktopCopyPath = desktop
                self.isDetecting = false
                self.refreshSignIn()
            }
        }
    }

    /// Force a fresh detection pass — used when the user may have just installed
    /// the CLI while the app was already running.
    func redetect() {
        hasRunDetection = false
        shellResolvedPath = nil
        desktopCopyPath = nil
        detectIfNeeded()
    }

    private func engineDidChange() {
        stop()
        cancelSignIn()
        installer.cancel()
        messages.removeAll()
        clearedConversation = nil; canUndoClear = false
        turn = nil; activityID = nil; answerID = nil
        sessionID = UUID().uuidString
        hasStartedSession = false
        codexThreadID = nil
        error = nil; errorDetails = nil; failedPrompt = nil
        signIn = nil
        redetect()
    }

    // MARK: - Sign-in

    /// Asks the CLI whether the user is signed in. A local read, well under a second.
    func refreshSignIn() {
        guard let binary = resolvedBinaryPath, !isCheckingSignIn else { return }
        #if DEBUG
        if let pinned = signInForSnapshot { signIn = pinned; return }
        #endif
        isCheckingSignIn = true
        let engine = self.engine
        Task.detached(priority: .utility) {
            let arguments = engine == .codex ? ["login", "status"] : ["auth", "status", "--json"]
            let answer = Self.runQuickly(binary, arguments, timeout: 15)
            let result: AgentSignIn
            if let answer {
                result = engine == .codex
                    ? AgentSignIn.parseCodex(output: answer.output, exitCode: answer.status)
                    : AgentSignIn.parseClaude(output: answer.output, exitCode: answer.status)
            } else {
                result = .unknown("\(engine.name) didn’t answer.")
            }
            await MainActor.run {
                self.isCheckingSignIn = false
                guard self.engine == engine else { return }
                self.signIn = result
                if case .signedIn = result, self.isWaitingForSignIn { self.finishSignIn() }
            }
        }
    }

    /// Runs the CLI's own sign-in. It opens the browser itself and listens on localhost;
    /// Ortus checks every 2 seconds and moves on when the CLI says the user is in.
    func startSignIn() {
        guard let binary = resolvedBinaryPath, signInProcess == nil else { return }
        // Codex's login signs you out first, so never start one while signed in.
        if case .signedIn = signIn { return }
        signInError = nil
        signInPageURL = nil
        signInOutput = ""
        isWaitingForSignIn = true

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = engine == .codex ? ["login"] : ["auth", "login"]
        process.environment = ProcessInfo.processInfo.environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                guard let self else { return }
                self.signInOutput += text
                if self.signInPageURL == nil { self.signInPageURL = AgentSignIn.signInURL(in: self.signInOutput) }
            }
        }
        process.terminationHandler = { [weak self] ended in
            let id = ObjectIdentifier(ended), status = ended.terminationStatus
            Task { @MainActor in self?.signInProcessEnded(id, status: status) }
        }
        do {
            try process.run()
        } catch {
            isWaitingForSignIn = false
            signInError = "\(engine.name) couldn’t start its sign-in. Try again."
            return
        }
        signInProcess = process
        signInInput = input.fileHandleForWriting

        signInPoll = Task { @MainActor [weak self] in
            let deadline = Date().addingTimeInterval(10 * 60)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.isWaitingForSignIn else { return }
                self.refreshSignIn()
            }
            guard let self, !Task.isCancelled, self.isWaitingForSignIn else { return }
            self.cancelSignIn()
            self.signInError = "Sign-in timed out. Try again."
        }
    }

    /// For when the sign-in page shows a code instead of coming back by itself.
    func submitSignInCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let input = signInInput else { return }
        try? input.write(contentsOf: Data((trimmed + "\n").utf8))
    }

    func reopenSignInPage() {
        guard let url = signInPageURL else { return }
        NSWorkspace.shared.open(url)
    }

    func cancelSignIn() {
        signInPoll?.cancel()
        signInPoll = nil
        if let process = signInProcess, process.isRunning { process.terminate() }
        signInProcess = nil
        signInInput = nil
        isWaitingForSignIn = false
    }

    private func finishSignIn() {
        cancelSignIn()
        signInError = nil
        Analytics.capture("agent_signed_in", ["engine": engine.rawValue])
    }

    private func signInProcessEnded(_ id: ObjectIdentifier, status: Int32) {
        guard let process = signInProcess, ObjectIdentifier(process) == id else { return }
        signInProcess = nil
        signInInput = nil
        // The CLI is done either way; its status check has the last word.
        if status == 0 {
            refreshSignIn()
        } else if isWaitingForSignIn {
            signInPoll?.cancel()
            isWaitingForSignIn = false
            signInError = "Sign-in didn’t finish. Try again."
        }
    }

    /// Runs a short CLI command and returns its combined output, or nil if it couldn't
    /// start or ran past `timeout`.
    nonisolated private static func runQuickly(_ binary: String, _ arguments: [String], timeout: TimeInterval) -> (output: String, status: Int32)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        // Terminated by the watchdog.
        if process.terminationReason == .uncaughtSignal { return nil }
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
    }

    /// Ask the user's login + interactive shell where the CLI lives. Using `-ilc`
    /// sources the same profile files the user's terminal does, so PATH additions
    /// from nvm/fnm/asdf/custom npm prefixes are visible — the common cases the
    /// static path list can't anticipate. Bounded by a watchdog so a slow or noisy
    /// shell profile can't hang detection.
    nonisolated private static func resolveViaLoginShell(_ name: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", "command -v \(name)"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Don't let an interactive profile that prompts or stalls hang us forever.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)

        // Read before waiting to avoid a full-pipe deadlock on chatty profiles.
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return nil }

        // `command -v` prints the resolved path; profiles may add noise, so take the
        // first line that's an absolute path to an executable file.
        for line in output.split(separator: "\n") {
            let candidate = line.trimmingCharacters(in: .whitespaces)
            if candidate.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Public API

    func retryLastMessage() {
        guard let prompt = failedPrompt, !isProcessing else { return }
        sendMessage(prompt, isRetry: true)
    }

    func sendMessage(_ text: String, isRetry: Bool = false) {
        guard !isProcessing else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let binary = resolvedBinaryPath else {
            failedPrompt = trimmed
            recordFailure("\(engine.name) could not be found. Open Agent setup to connect your installation.")
            return
        }

        clearedConversation = nil; canUndoClear = false
        if !isRetry { messages.append(ChatMessage(role: .user, content: trimmed)) }
        let newTurn = ChatTurn(startedAt: Date(), format: engine == .codex ? .codex : .claudeCode)
        let activity = ChatMessage(role: .assistant, content: "", kind: .activity(newTurn.activity))
        messages.append(activity)
        turn = newTurn; activityID = activity.id; answerID = nil
        isProcessing = true
        error = nil
        errorDetails = nil
        failedPrompt = nil

        let isFirstTurn = !hasStartedSession
        Analytics.capture("chat_message_sent", ["is_first_message": isFirstTurn, "engine": engine.rawValue])
        let arguments = engine == .codex
            ? AgentCommand.codexTurn(prompt: trimmed, systemPrompt: systemPromptNow(), threadID: codexThreadID,
                                     workingDirectory: Self.codexFolder().path)
            : claudeArguments(prompt: trimmed, isFirstTurn: isFirstTurn)

        currentTask = Task { @MainActor in
            await runAgent(binary: binary, arguments: arguments)
            self.updateTurn { $0.finish(at: Date(), stopped: Task.isCancelled) }
            if self.error != nil { self.failedPrompt = trimmed }
            self.isProcessing = false
            self.currentProcess = nil
            self.currentTask = nil
        }
    }

    /// The draft card's Send button: a normal chat message, like typing it. Edits go
    /// along in full so Claude sends the user's version.
    func sendDraft(id: String, original: String, edited: String) {
        guard !isProcessing else { return }
        let text = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        sendMessage(text == original.trimmingCharacters(in: .whitespacesAndNewlines) ? "Send it." : "Send it, with my edits:\n\n\(text)")
        sentDrafts[id] = text
    }

    func stop() {
        currentProcess?.terminate()
        currentTask?.cancel()
    }

    func clearConversation() {
        guard !isProcessing else { return }
        clearedConversation = (messages, sessionID, hasStartedSession)
        canUndoClear = !messages.isEmpty
        stop()
        Analytics.capture("chat_cleared", ["message_count": messages.count])
        messages.removeAll()
        turn = nil; activityID = nil; answerID = nil
        sessionID = UUID().uuidString
        hasStartedSession = false
        codexThreadID = nil
        error = nil
        errorDetails = nil
        failedPrompt = nil
    }

    func undoClear() {
        guard !isProcessing, messages.isEmpty, let previous = clearedConversation else { return }
        messages = previous.messages; sessionID = previous.sessionID; hasStartedSession = previous.started
        clearedConversation = nil; canUndoClear = false
    }

    // MARK: - Subprocess

    private func systemPromptNow() -> String {
        Self.systemPrompt(now: Date(), focus: focusContext(), version: Self.versionLine)
    }

    private func claudeArguments(prompt: String, isFirstTurn: Bool) -> [String] {
        [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--model", "claude-sonnet-5-5",
            "--effort", "low",
            "--append-system-prompt", systemPromptNow(),
            // Every tool is on, like Claude Code in the user's terminal. The prompt has it
            // draft anything that sends or changes something and wait for the user's OK.
            "--permission-mode", "bypassPermissions",
        ] + (isFirstTurn ? ["--session-id", sessionID] : ["--resume", sessionID])
    }

    /// Codex works in a folder only Ortus uses: no project files, no git checks.
    private static func codexFolder() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ortusmode.preview", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func runAgent(binary: String, arguments: [String]) async {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: binary)
        process.standardOutput = stdout
        process.standardError = stderr
        // Codex reads stdin to the end when it isn't a terminal: give it nothing to wait for.
        process.standardInput = FileHandle.nullDevice
        // Carry through HOME / PATH / etc so the CLI finds its config and the user's auth.
        process.environment = ProcessInfo.processInfo.environment
        process.arguments = arguments

        currentProcess = process
        let name = engine.name

        do {
            try process.run()
        } catch {
            recordFailure("\(name) could not start. Check its location in Agent setup, then retry.", details: error.localizedDescription)
            return
        }

        // Drain stderr concurrently so verbose errors cannot fill the pipe and stall Claude.
        let stderrReader = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }

        // Stream stdout line by line. Each line is a JSON event.
        do {
            for try await line in stdout.fileHandleForReading.bytes.lines {
                if Task.isCancelled { break }
                handleStreamLine(line)
            }
        } catch {
            // Pipe read error — usually means cancellation. Fall through to exit handling.
        }

        // Drain whatever's left and wait for the process to finish.
        process.waitUntilExit()

        let stderrData = await stderrReader.value
        if process.terminationStatus != 0 && !Task.isCancelled && error == nil {
            let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = stderrText.isEmpty
                ? "\(engine.binaryName) exited with status \(process.terminationStatus)."
                : stderrText
            recordTurnFailure(message)
        }
    }

    /// A turn that failed: says so in the chat, and notices a sign-out so the Agent tab
    /// can offer to sign in again instead of a generic error.
    private func recordTurnFailure(_ details: String) {
        if AgentSignIn.meansSignedOut(details) {
            signIn = .signedOut
            recordFailure("You’re signed out of \(engine.name). Sign in again, then retry.", details: details)
            return
        }
        recordFailure("\(engine.name) could not finish this request. Check your connection and Agent setup, then retry.", details: details)
        // Codex's errors don't always say it's a sign-in problem: ask it.
        if engine == .codex { refreshSignIn() }
    }

    private func recordFailure(_ message: String, details: String? = nil) {
        error = message
        errorDetails = details
        messages.append(ChatMessage(role: .assistant, content: message, kind: .error))
    }

    // MARK: - Stream parsing

    private func handleStreamLine(_ line: String) {
        guard !line.isEmpty else { return }
        updateTurn { $0.consume(line, at: Date()) }
    }

    /// Applies a change to the current answer and mirrors it into the chat rows:
    /// the activity row updates in place, the answer appears under it (and leaves
    /// again if it turns out to be narration before a tool call), and an error is
    /// added once the answer is finished.
    private func updateTurn(_ change: (inout ChatTurn) -> Void) {
        guard var current = turn else { return }
        let wasFinished = current.isFinished
        change(&current)
        turn = current
        if current.didStartSession { hasStartedSession = true }
        if let thread = current.threadID { codexThreadID = thread }

        guard let activityIndex = messages.firstIndex(where: { $0.id == activityID }) else { return }
        messages[activityIndex].kind = .activity(current.activity)

        let answerIndex = messages.firstIndex { $0.id == answerID }
        switch (answerIndex, current.answer.isEmpty) {
        case (nil, false):
            let answer = ChatMessage(role: .assistant, content: current.answer)
            messages.insert(answer, at: activityIndex + 1)
            answerID = answer.id
        case (let index?, false):
            if messages[index].content != current.answer { messages[index].content = current.answer }
        case (let index?, true):
            messages.remove(at: index)
            answerID = nil
        case (nil, true):
            break
        }

        guard current.isFinished, !wasFinished else { return }
        if let failure = current.failure { recordTurnFailure(failure) }
    }

    // MARK: - System prompt

    /// "Ortus 1.1.3 on macOS 15.1", so feedback emails say which build had the problem.
    static var versionLine: String {
        let app = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "Ortus \(app) on macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    /// Rebuilt for every message: each one starts a new `claude` process (resuming the
    /// same session), so the time and the focus state are always current.
    static func systemPrompt(now: Date, focus: String?, version: String) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        let today = "Right now it is \(clock.string(from: now)) (\(TimeZone.current.identifier))."
        return """
        You are the assistant inside Ortus, a macOS focus app. The apps and websites that distract the user \
        (for example Slack, email, social media) are blocked while they focus. They use this chat to find \
        information or get small tasks done without opening those apps. Answer what they asked and protect \
        their attention.

        \(today)
        \(focus ?? "")
        This is \(version).

        Guidelines:
        - Use whatever connected tools fit the request: Slack, email, calendar, documents, the web.
        - Answer in the first sentence. Skip preamble. Don't narrate what you're about to do.
        - Show only what matters for the question. If the answer is no or nothing, say so in one line and \
        stop: don't list what else you came across (other channels, newsletters, promotions, past events, \
        "they did post elsewhere…").
        - For "anything urgent?" questions, mention only what needs the user before their session ends or \
        today. Everything else is one short closing line at most, without names.
        - Resolve user IDs to display names before showing them.
        - Never send or change anything (a message, an email, a document, an invite) until the user says \
        so. When they ask you to write, draft or reply to something, show it as a draft block (format below) \
        and stop. That block is the draft: even for "a Gmail draft", don't create or edit drafts in Gmail or \
        another app unless they explicitly ask to save it there. To change a draft (text, recipients), reply \
        with the updated draft block.
        - The draft card has a Send button. End your reply with the draft block: no line about how to send \
        it or what to say (no 'Say "Send it."'). Send replies "Send it." or \
        "Send it, with my edits:" followed by their text. Then send exactly that text, to the recipients in \
        the draft, and confirm in one short line.
        - When the user reports a bug or a problem with Ortus, or has feedback or an idea for it, offer to \
        email the Ortus team at support@ortusmode.com and draft it in the same reply: a short subject, what \
        happened or what they'd like, in their words, and the Ortus and macOS versions. If you can send email \
        (a Gmail tool, for example), it's a normal draft block to support@ortusmode.com. If you can't, write \
        the address in plain text and use "source: email" in the draft block: Ortus then shows a Copy button \
        instead of Send.

        - When the user asks for a verification, login, 2FA or one-time code (or a sign-in code from an \
        email or message), find the newest one that fits and start your reply with a verification block, \
        so Ortus shows the code big with a Copy button, the sender and the time. Then one short line with \
        anything else they need (it was the only recent code, it's for another account). Don't repeat the \
        code, sender or time in the text. If you find several recent codes and can't tell which one they mean, \
        show the newest and name the others in one line. If there is none, say so in one line.

        ```verification
        code: 526858
        from: OpenRouter
        source: gmail
        time: 2026-11-07T17:03:00+01:00
        ```

        The code is copied exactly from the message. source is gmail, slack or other; time is ISO 8601 \
        with offset, copied from the tool result.

        Formatting (the chat panel is narrow, about 50 characters per line):
        - Short paragraphs. A bullet list only for three or more parallel items. Bold sparingly, for names \
        or the key fact.
        - No headings, no tables, no emoji unless the user uses them first.
        - Times in the user's local time, relative when close ("yesterday at 11:37", "Thursday at 9:00"). \
        Never write time zone names.

        Quoting messages: when you show what someone actually wrote (a Slack message or thread, an email, a \
        social post), put it in a quote block so Ortus shows it as a card. Text inside is copied verbatim \
        from the tool result; shorten long text with "…" but never reword it. When the user asks what a \
        message, email or post said, quote it rather than paraphrasing; open the full message if you only \
        have a preview. Quote only the messages that answer the question, usually one to four; summarize \
        the rest in a sentence outside the block. Don't repeat in prose or bullets what the quote already \
        says. Format:

        ```quote
        source: slack
        place: #general
        ---
        from: Maya Chen
        time: 2026-10-25T10:12:00+00:00

        The pricing page won't be ready for Friday…
        ---
        skipped: 4
        ---
        from: Tom Price
        time: 2026-10-25T10:37:00+00:00

        Agreed
        ```

        - source is slack, gmail, linkedin, x or other. place is the channel ("#general", "DM with Maya"), \
        the email subject, or the site.
        - One section per message, oldest first, separated by "---". Header lines, then a blank line, then \
        the text.
        - For a thread, include the parent and only the replies that matter; a "skipped: N" section marks \
        replies you left out (don't explain the skipping in prose).
        - Emails may add "to:" under "from:". Posts may add "about:" with the author's headline.
        - Times are ISO 8601 with offset, copied from the tool result.

        Draft blocks use the same format with "draft" instead of "quote": source and place (the channel or \
        the email subject) in the header, then one section with "to:", "cc:" for anyone copied, and the \
        text. Write the text exactly as it will be sent, in the user's voice, without placeholders.

        ```draft
        source: gmail
        place: Re: Q1 pilot proposal
        ---
        to: Sara Conti

        Hi Sara, 12 January works for us.
        ```
        """
    }
}
