import SwiftUI
import ServiceManagement
import OrtusCore

/// Every setting is the same kind of row: icon, title, one line of status, one control.
struct SettingsView: View {
    @EnvironmentObject var focusManager: FocusManager
    @EnvironmentObject var slackOAuthService: SlackOAuthService
    @EnvironmentObject var claudeCodeService: ClaudeCodeService
    @EnvironmentObject var updateService: UpdateService
    @EnvironmentObject var router: PanelRouter
    @Environment(\.snapshotState) private var snapshotState

    @State private var launchAtLogin = false
    @State private var versionTapCount = 0
    @State private var showSlackPreview = false
    @State private var taglineIndex = 0
    @AppStorage("genZMode") private var genZ = false
    @AppStorage(Analytics.consentKey) private var shareUsage = false
    /// Experimental features sit in a section that starts closed.
    @AppStorage("showExperimentalSettings") private var showExperimental = false

    /// Tapping the mark cycles these. "Latin for rising" lives here and nowhere else.
    private let taglines = [
        "No end button.",
        "Ortus is Latin for rising.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Connections") {
                    BrowserStatusRow(service: focusManager.websites)
                    OrtusGroupDivider()
                    chatRow
                }

                if focusManager.isInFocus && !focusManager.isInGracePeriod {
                    section("Emergency") { emergencyRow }
                }

                section("General") {
                    OrtusListRow(title: "Open at login") {
                        OrtusIcon(.power, size: 18)
                    } trailing: {
                        toggle($launchAtLogin)
                    }
                    OrtusGroupDivider()
                    OrtusListRow(title: "Share anonymous usage", subtitle: "Which features get used. Never messages or sites") {
                        OrtusIcon(.bars, size: 18)
                    } trailing: {
                        toggle($shareUsage)
                    }
                    OrtusGroupDivider()
                    OrtusListRow(title: "Gen Z mode", subtitle: genZ ? "it’s giving focus" : "Rewrites Ortus in Gen Z") {
                        OrtusIcon(.spark, size: 18)
                    } trailing: {
                        toggle($genZ)
                    }
                    // Previews never check for updates; snapshots pin a state to show the rows.
                    if !BuildProfile.isPreview || snapshotState != nil, let update = updateRow {
                        OrtusGroupDivider()
                        update
                    }
                    OrtusGroupDivider()
                    feedbackRow
                    OrtusGroupDivider()
                    aboutRow
                }

                experimentalSection
            }
            .padding(OrtusTheme.spacingMD)
        }
        .onAppear {
            // Snapshots show the section closed, except the one state that opens it.
            if snapshotState != nil { showExperimental = ["settings-experimental", "settings-codex"].contains(snapshotState) }
            claudeCodeService.detectIfNeeded()
            // Read the real login-item state; the toggle must never guess.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
        .onChange(of: shareUsage) { _, newValue in Analytics.setConsent(newValue) }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            OrtusSectionHeader(title: title).padding(.horizontal, 4)
            OrtusGroup { content() }
        }
    }

    private func toggle(_ isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn).labelsHidden().toggleStyle(OrtusToggleStyle())
    }

    // MARK: - Connections

    private var slackRow: some View {
        OrtusListRow(title: "Slack status",
                     subtitle: slackOAuthService.isConnected ? "Connected to \(slackOAuthService.teamName ?? "Slack")" : "Status and Do Not Disturb while you focus") {
            OrtusIcon(.hash, size: 18)
        } trailing: {
            if slackOAuthService.isConnected {
                Button("Disconnect") { slackOAuthService.disconnect() }.buttonStyle(OrtusRowButtonStyle())
            } else {
                Button("Connect") { router.modal = .slackSetup }.buttonStyle(OrtusRowButtonStyle())
            }
        }
    }

    /// Ready, signed out or not set up, naming Codex when it's the engine.
    private var chatRow: some View {
        let service = claudeCodeService
        let status = !service.isConfigured ? "Not set up" : service.isSignedOut ? "Signed out" : "Ready"
        let isFine = service.isConfigured && !service.isSignedOut
        return OrtusListRow(title: "Agent", subtitle: service.engine == .codex ? "Codex · \(status)" : status) {
            if isFine { OrtusIcon(.check, size: 18) } else { OrtusProblemIcon(size: 18) }
        } trailing: {
            if isFine {
                Button("Change") { router.modal = .chatSetup }.buttonStyle(OrtusGhostButtonStyle())
            } else {
                Button("Set up") { router.modal = .chatSetup }.buttonStyle(OrtusPrimaryButtonStyle(size: .small))
            }
        }
    }

    // MARK: - Experimental

    /// Closed by default: a header that opens to features that may still change.
    private var experimentalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.18)) { showExperimental.toggle() } } label: {
                HStack(spacing: 6) {
                    OrtusSectionHeader(title: "Experimental")
                    OrtusIcon(.chevronDown, size: 9).foregroundStyle(OrtusTheme.textMuted)
                        .rotationEffect(.degrees(showExperimental ? 0 : -90))
                    Spacer()
                }
                .padding(.horizontal, 4).padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(OrtusPressableStyle(cornerRadius: 8))
            .accessibilityLabel("Experimental")
            .accessibilityValue(showExperimental ? "Expanded" : "Collapsed")

            if showExperimental {
                OrtusGroup {
                    slackRow
                    if slackOAuthService.isConnected {
                        OrtusGroupDivider()
                        slackStatusRows
                    }
                    OrtusGroupDivider()
                    codexRow
                }
            }
        }
    }

    /// Runs the agent on Codex instead of Claude Code, for people on a ChatGPT plan.
    /// Turning it on opens Agent setup, which finds, installs or signs in to Codex.
    private var codexRow: some View {
        OrtusListRow(title: "Codex instead of Claude Code", subtitle: "Run your agent on a ChatGPT plan. Starts a new conversation.") {
            OrtusIcon(.terminal, size: 18)
        } trailing: {
            toggle(Binding(
                get: { claudeCodeService.engine == .codex },
                set: { useCodex in
                    claudeCodeService.engine = useCodex ? .codex : .claudeCode
                    Analytics.capture("agent_engine_changed", ["engine": claudeCodeService.engine.rawValue])
                    if useCodex { router.modal = .chatSetup }
                }
            ))
        }
    }

    @ViewBuilder private var slackStatusRows: some View {
        OrtusListRow(title: "Set my status") { OrtusIcon(.chat, size: 18) } trailing: { toggle($focusManager.slackStatusEnabled) }
        if focusManager.slackStatusEnabled {
            OrtusGroupDivider()
            HStack(spacing: 14) {
                EmojiPickerButton(code: $focusManager.slackStatusEmoji).frame(width: 22)
                TextField("", text: $focusManager.slackStatusText, prompt: Text("Ortus mode").foregroundStyle(OrtusTheme.textMuted))
                    .textFieldStyle(.plain).font(OrtusTheme.Typo.bodyMedium)
                    .accessibilityLabel("Status text")
                Button(showSlackPreview ? "Hide preview" : "Preview") { showSlackPreview.toggle() }.buttonStyle(OrtusRowButtonStyle())
            }
            .padding(.horizontal, OrtusTheme.spacingMD).padding(.vertical, 11)
            if showSlackPreview {
                SlackStatusPreview(statusText: focusManager.slackStatusText, emojiCode: focusManager.slackStatusEmoji,
                                   userName: "Example user", dndEnabled: focusManager.slackDndEnabled)
                    .padding([.horizontal, .bottom], OrtusTheme.spacingMD)
            }
        }
        OrtusGroupDivider()
        OrtusListRow(title: "Do Not Disturb") { OrtusIcon(.hide, size: 18) } trailing: { toggle($focusManager.slackDndEnabled) }
    }

    // MARK: - Emergency

    private var emergencyRow: some View {
        OrtusListRow(title: "End focus early",
                     subtitle: focusManager.canUseEmergencyEnd
                        ? "For real emergencies. 1 left this week."
                        : "Available again \(focusManager.nextEmergencyAvailableDate?.formatted(date: .abbreviated, time: .shortened) ?? "next week")") {
            OrtusIcon(.locked, size: 18).foregroundStyle(OrtusTheme.accent)
        } trailing: {
            if focusManager.canUseEmergencyEnd {
                Button("End early") { router.modal = .endFocusEarly }.buttonStyle(OrtusSecondaryButtonStyle(size: .small))
            }
        }
    }

    // MARK: - General

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0-preview"
    }

    private var aboutRow: some View {
        OrtusListRow(title: "Ortus \(appVersion)",
                     subtitle: focusManager.isInFocus ? "You can quit after this session" : taglines[taglineIndex]) {
            OrtusMark(width: 22)
                .onTapGesture {
                    taglineIndex = (taglineIndex + 1) % taglines.count
                    versionTapCount += 1
                    if versionTapCount >= 7 { focusManager.developerModeEnabled.toggle(); versionTapCount = 0 }
                }
        } trailing: {
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(OrtusRowButtonStyle())
                .disabled(focusManager.isInFocus)
        }
    }

    private var feedbackRow: some View {
        OrtusListRow(title: "Send feedback") {
            OrtusIcon(.mail, size: 18)
        } trailing: {
            Button("Email us") { NSWorkspace.shared.open(feedbackEmail) }.buttonStyle(OrtusRowButtonStyle())
        }
    }

    /// A new email in the user's mail app, with the versions filled in for bug reports.
    private var feedbackEmail: URL {
        var email = URLComponents(string: "mailto:support@ortusmode.com")!
        email.queryItems = [URLQueryItem(name: "subject", value: "Ortus feedback"),
                            URLQueryItem(name: "body", value: "\n\n\n\(ClaudeCodeService.versionLine)")]
        return email.url!
    }

    private var updateRow: AnyView? {
        switch updateService.state {
        case let .available(version):
            return AnyView(OrtusListRow(title: "Update available",
                                        subtitle: !updateService.installsAfterFocus ? "Version \(version)"
                                            : focusManager.isInFocus ? "Version \(version) · installs an hour after this session"
                                            : "Version \(version) · installs within the hour") {
                OrtusIcon(.update, size: 18)
            } trailing: {
                if focusManager.isInFocus && updateService.installsAfterFocus {
                    EmptyView()
                } else if focusManager.isInFocus {
                    Button("Update after session") { updateService.installAfterFocus(focusManager) }
                        .buttonStyle(OrtusRowButtonStyle())
                } else {
                    Button("Restart and update") { Task { await updateService.downloadAndInstall(isInFocus: false) } }
                        .buttonStyle(OrtusPrimaryButtonStyle(size: .small))
                }
            })
        case .downloading:
            return AnyView(OrtusListRow(title: "Updating", subtitle: "Ortus will restart") {
                ProgressView().controlSize(.small)
            } trailing: { EmptyView() })
        case let .failed(message):
            return AnyView(OrtusListRow(title: "Update not installed", subtitle: message) {
                OrtusProblemIcon(size: 18)
            } trailing: {
                // Fetch the release again and install it, rather than only checking.
                Button("Try again") {
                    Task {
                        await updateService.checkForUpdates()
                        await updateService.downloadAndInstall(isInFocus: focusManager.isInFocus)
                    }
                }
                    .buttonStyle(OrtusRowButtonStyle())
            })
        case .upToDate:
            return AnyView(OrtusListRow(title: "You’re on the latest version") {
                OrtusIcon(.check, size: 18)
            } trailing: { EmptyView() })
        case .idle, .checking:
            return nil
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // Swallow; the re-sync below pulls the actual state from macOS.
        }
        let actual = SMAppService.mainApp.status == .enabled
        if launchAtLogin != actual { launchAtLogin = actual }
    }
}

// MARK: - Agent setup

/// One popup walks through everything the agent needs: find the CLI (or install it),
/// sign in, done. Each screen shows only when it's needed: someone with Claude Code
/// installed and signed in only ever sees "Ortus Agent is ready".
struct ChatSetupModal: View {
    @EnvironmentObject var claudeCodeService: ClaudeCodeService

    var body: some View {
        AgentSetupSheet(service: claudeCodeService, installer: claudeCodeService.installer)
    }
}

private struct AgentSetupSheet: View {
    @ObservedObject var service: ClaudeCodeService
    @ObservedObject var installer: AgentInstaller
    @EnvironmentObject var router: PanelRouter
    @Environment(\.snapshotState) private var snapshotState
    @State private var pathError: String?
    @State private var showsCodeField = false
    @State private var code = ""
    @State private var copiedCommand = false

    private enum Step: Equatable { case looking, notFound, installing, signIn, waiting, ready }

    private var name: String { service.engine.name }
    private var isCodex: Bool { service.engine == .codex }

    private var step: Step {
        if service.isConfigured {
            if service.isWaitingForSignIn { return .waiting }
            switch service.signIn {
            case nil: return .looking
            case .signedOut?: return .signIn
            default: return .ready
            }
        }
        if installer.phase != .idle { return .installing }
        // Still looking (the login-shell search takes a moment): don't call it missing yet.
        if service.isDetecting || snapshotState == "agent-setup-checking" { return .looking }
        return .notFound
    }

    var body: some View {
        OrtusModal(title: "Agent setup", onClose: { router.modal = nil }) {
            // The whole sheet changes at each step, so the switch can't be missed.
            Group {
                switch step {
                case .looking: looking.transition(.opacity)
                case .notFound: notFound.transition(.opacity)
                case .installing: installing.transition(.opacity)
                case .signIn: signIn.transition(.opacity)
                case .waiting: waiting.transition(.opacity)
                case .ready: ready.transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.25), value: step)
        }
        .onAppear {
            if snapshotState == "agent-setup-error" { pathError = Self.notRunnable(service.engine) }
            // Ortus checks again every time this opens, so there's no "Check again".
            guard snapshotState == nil else { return }
            if !service.isConfigured, installer.phase == .idle { service.redetect() } else { service.refreshSignIn() }
        }
    }

    // MARK: Screens

    private var looking: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(service.isConfigured ? "Checking your sign-in…" : "Looking for \(name)…")
                .font(OrtusTheme.Typo.callout).foregroundStyle(OrtusTheme.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    /// Not found: one clear action. Finding it yourself is a text link, for an install
    /// in an odd place.
    private var notFound: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            VStack(spacing: 10) {
                OrtusProblemIcon(size: 28)
                headline("Ortus Agent requires \(name).")
                if isCodex {
                    caption("Free download from OpenAI. OpenAI’s installer also lets you use Codex in Terminal.")
                }
            }
            Button("Install \(name)") { installer.install(service.engine) }
                .buttonStyle(OrtusPrimaryButtonStyle(fullWidth: true))
                .keyboardShortcut(.defaultAction)
            if let pathError { problemLine(pathError) }
            Button("Already installed? Find it", action: chooseFile)
                .buttonStyle(OrtusGhostButtonStyle())
        }
    }

    /// One bar and one line that changes. The steps underneath aren't worth explaining.
    @ViewBuilder private var installing: some View {
        if case .failed(let message, _) = installer.phase {
            VStack(spacing: OrtusTheme.spacingMD) {
                OrtusProblemIcon(size: 28)
                headline(message)
                Button("Try again") { installer.install(service.engine) }
                    .buttonStyle(OrtusPrimaryButtonStyle(fullWidth: true))
                    .keyboardShortcut(.defaultAction)
                Button(copiedCommand ? "Copied. Paste it in Terminal." : "Install in Terminal instead") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AgentInstaller.terminalCommand(for: service.engine), forType: .string)
                    copiedCommand = true
                }
                .buttonStyle(OrtusGhostButtonStyle())
            }
        } else {
            VStack(spacing: OrtusTheme.spacingMD) {
                VStack(spacing: 10) {
                    tile(.update)
                    headline("Installing \(name)")
                }
                VStack(spacing: 8) {
                    if let fraction = installFraction {
                        OrtusLineProgress(fraction: fraction)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    HStack {
                        Text(installLabel).font(OrtusTheme.Typo.caption.weight(.bold))
                        Spacer()
                        if case .downloading(let received, let total) = installer.phase, total > 0 {
                            Text("\(Self.megabytes(received)) of \(Self.megabytes(total)) MB")
                                .font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
                                .monospacedDigit()
                        }
                    }
                }
                caption("You can close this. Setup carries on.")
                // Stopping the CLI's own setup halfway could leave a broken install.
                if installer.phase != .settingUp {
                    Button("Cancel") { installer.cancel() }
                        .buttonStyle(OrtusSecondaryButtonStyle(size: .small))
                }
            }
        }
    }

    private var installFraction: Double? {
        switch installer.phase {
        case .downloading(let received, let total): total > 0 ? Double(received) / Double(total) : nil
        case .checking, .done: 1
        default: nil
        }
    }

    private var installLabel: String {
        switch installer.phase {
        case .downloading: "Downloading"
        case .checking: "Checking it’s from \(isCodex ? "OpenAI" : "Anthropic")"
        default: "Setting up"
        }
    }

    private var signIn: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            VStack(spacing: 10) {
                tile(.agent)
                headline("Sign in to \(name)")
                caption(isCodex
                    ? "Sign in with your ChatGPT account on OpenAI’s page, then come back here. Ortus never sees your password."
                    : "Approve on claude.ai, then come back here. Ortus never sees your password.")
            }
            if let error = service.signInError { problemLine(error) }
            Button(isCodex ? "Sign in with ChatGPT" : "Sign in") { service.startSignIn() }
                .buttonStyle(OrtusPrimaryButtonStyle(fullWidth: true))
                .keyboardShortcut(.defaultAction)
        }
    }

    private var waiting: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            VStack(spacing: 10) {
                ProgressView().controlSize(.regular)
                headline("Finish in your browser")
                caption(isCodex
                    ? "Sign in on OpenAI’s page. This moves on by itself when you’re done."
                    : "Approve Claude Code on claude.ai. This moves on by itself when you’re done.")
            }
            HStack(spacing: 4) {
                if service.signInPageURL != nil {
                    Button("Open the page again") { service.reopenSignInPage() }.buttonStyle(OrtusGhostButtonStyle())
                }
                // Claude Code's page sometimes shows a code to paste back instead.
                if !isCodex && !showsCodeField {
                    Button("Got a code? Paste it") { showsCodeField = true }.buttonStyle(OrtusGhostButtonStyle())
                }
            }
            if showsCodeField {
                HStack(spacing: OrtusTheme.spacingSM) {
                    TextField("", text: $code, prompt: Text("Code from claude.ai").foregroundStyle(OrtusTheme.textMuted))
                        .textFieldStyle(OrtusTextFieldStyle())
                        .accessibilityLabel("Sign-in code")
                        .onSubmit(sendCode)
                    Button("Send", action: sendCode)
                        .buttonStyle(OrtusPrimaryButtonStyle(size: .small))
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Button("Cancel") { service.cancelSignIn() }
                .buttonStyle(OrtusSecondaryButtonStyle(size: .small))
        }
    }

    private func sendCode() {
        service.submitSignInCode(code)
        code = ""
        showsCodeField = false
    }

    /// Done. Names the account, so you know it worked.
    private var ready: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            tile(.check, size: 60)
            VStack(spacing: 6) {
                Text("Ortus Agent is ready")
                    .font(OrtusTheme.Typo.titleSmall)
                    .tracking(-1)
                    .multilineTextAlignment(.center)
                if let account = accountLine {
                    Text(account).font(OrtusTheme.Typo.callout).foregroundStyle(OrtusTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 2) {
                    Text(((service.resolvedBinaryPath ?? "") as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(OrtusTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Change", action: chooseFile)
                        .buttonStyle(OrtusGhostButtonStyle())
                        .help("Choose another \(name)")
                }
            }
            if let pathError { problemLine(pathError) }
            Button("Start", action: start)
                .buttonStyle(OrtusPrimaryButtonStyle(fullWidth: true))
                .keyboardShortcut(.defaultAction)
        }
    }

    /// "Signed in as you@gmail.com, Max plan", "Signed in with ChatGPT".
    private var accountLine: String? {
        switch service.signIn {
        case .signedIn(let email, let plan)?:
            if plan == "ChatGPT" { return email.map { "Signed in as \($0), with ChatGPT" } ?? "Signed in with ChatGPT" }
            let parts = [email.map { "Signed in as \($0)" } ?? "Signed in", plan].compactMap { $0 }
            return parts.joined(separator: ", ")
        case .unknown?: return "Ortus couldn’t check the sign-in. Your first message will tell."
        default: return nil
        }
    }

    /// Closes the popup and puts the cursor in the Agent tab's text box.
    private func start() {
        router.modal = nil
        router.requestedTab = 2
        router.focusChatInput = true
    }

    // MARK: Parts

    private func headline(_ text: String) -> some View {
        Text(text)
            .font(OrtusTheme.Typo.cardTitle)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(OrtusTheme.Typo.caption)
            .foregroundStyle(OrtusTheme.textMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ icon: OrtusIcon.Name, size: CGFloat = 52) -> some View {
        OrtusIcon(icon, size: size * 0.48)
            .foregroundStyle(OrtusTheme.onStrong)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous).fill(OrtusTheme.strong))
    }

    private func problemLine(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            OrtusProblemIcon(size: 16)
            Text(message).font(OrtusTheme.Typo.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func notRunnable(_ engine: AgentEngine) -> String {
        "That file can’t be run. Choose the file named \(engine.binaryName)."
    }

    private static func megabytes(_ bytes: Int64) -> Int { Int((Double(bytes) / 1_000_000).rounded()) }

    /// The file picker behind "Find it" and "Change". Hidden folders show, since the
    /// installers put the CLI in ~/.local/bin.
    private func chooseFile() {
        let engine = service.engine
        let panel = NSOpenPanel()
        panel.title = "Find \(engine.name)"
        panel.message = "Choose the file named \(engine.binaryName)."
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        // Keep ~/.local/bin/claude as chosen, not the version folder it links to: that
        // changes every time the CLI updates itself.
        panel.resolvesAliases = false
        let home = FileManager.default.homeDirectoryForCurrentUser
        let localBin = home.appendingPathComponent(".local/bin", isDirectory: true)
        panel.directoryURL = service.resolvedBinaryPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
            ?? (FileManager.default.fileExists(atPath: localBin.path) ? localBin : home)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard ClaudeLocation.isRunnable(url.path) else {
                pathError = Self.notRunnable(engine)
                return
            }
            pathError = nil
            service.chosenPath = url.path
            service.redetect()
        }
    }
}

// MARK: - Slack setup

struct SlackSetupModal: View {
    @EnvironmentObject var slackOAuthService: SlackOAuthService
    @EnvironmentObject var router: PanelRouter
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var copied = false

    var body: some View {
        OrtusModal(title: "Connect Slack", onClose: { router.modal = nil }) {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                Text("Ortus sets your status through a Slack app you own. It takes about two minutes.")
                    .font(OrtusTheme.Typo.callout).foregroundStyle(OrtusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                OrtusGroup {
                    OrtusStepRow(number: 1, title: "Create a Slack app") {
                        Link("Open Slack", destination: URL(string: "https://api.slack.com/apps?new_app=1")!)
                            .buttonStyle(OrtusSecondaryButtonStyle(size: .small))
                    }
                    OrtusGroupDivider()
                    OrtusStepRow(number: 2, title: "Add this redirect URL", detail: "OAuth & Permissions → Redirect URLs\n\(SlackOAuthService.callbackURL)") {
                        Button(copied ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(SlackOAuthService.callbackURL, forType: .string)
                            copied = true
                        }
                        .buttonStyle(OrtusSecondaryButtonStyle(size: .small))
                    }
                    OrtusGroupDivider()
                    OrtusStepRow(number: 3, title: "Paste the Client ID and Secret", detail: "Basic Information → App Credentials") { EmptyView() }
                }
                TextField("", text: $clientID, prompt: Text("Client ID").foregroundStyle(OrtusTheme.textMuted)).textFieldStyle(OrtusTextFieldStyle())
                    .accessibilityLabel("Client ID")
                SecureField("", text: $clientSecret, prompt: Text("Client Secret").foregroundStyle(OrtusTheme.textMuted)).textFieldStyle(OrtusTextFieldStyle())
                    .accessibilityLabel("Client Secret")
                if let error = slackOAuthService.error {
                    HStack(alignment: .top, spacing: 8) {
                        OrtusProblemIcon(size: 16)
                        Text(error).font(OrtusTheme.Typo.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    if slackOAuthService.isAuthenticating {
                        ProgressView().controlSize(.small)
                        Text("Waiting for Slack…").font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
                    }
                    Spacer()
                    Button("Connect Slack") {
                        do {
                            try KeychainService.save(clientID, for: .slackClientId)
                            try KeychainService.save(clientSecret, for: .slackClientSecret)
                        } catch {
                            slackOAuthService.error = error.localizedDescription
                            return
                        }
                        slackOAuthService.invalidateCredentialsCache()
                        slackOAuthService.startOAuthFlow()
                    }
                    .buttonStyle(OrtusPrimaryButtonStyle())
                    .disabled(clientID.isEmpty || clientSecret.isEmpty)
                }
            }
        }
        // Load the saved credentials once, when the form opens. The fields hold edits until Connect Slack.
        .onAppear {
            clientID = KeychainService.load(.slackClientId) ?? ""
            clientSecret = KeychainService.load(.slackClientSecret) ?? ""
        }
        .onChange(of: slackOAuthService.isConnected) { _, connected in if connected { router.modal = nil } }
    }
}
