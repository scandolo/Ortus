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
            if snapshotState != nil { showExperimental = snapshotState == "settings-experimental" }
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

    /// "Ready" only means Claude Code was found on this Mac, as in Agent setup.
    private var chatRow: some View {
        OrtusListRow(title: "Agent", subtitle: claudeCodeService.isConfigured ? "Ready" : "Not set up") {
            if claudeCodeService.isConfigured { OrtusIcon(.check, size: 18) } else { OrtusProblemIcon(size: 18) }
        } trailing: {
            if claudeCodeService.isConfigured {
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
                }
            }
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
        case let .available(version) where !updateService.canInstallInPlace:
            return AnyView(OrtusListRow(title: "Update available",
                                        subtitle: "Version \(version) · Ortus can’t update itself from this Mac account") {
                OrtusIcon(.update, size: 18)
            } trailing: {
                Button("Download") { NSWorkspace.shared.open(UpdateService.downloadPage) }
                    .buttonStyle(OrtusPrimaryButtonStyle(size: .small))
            })
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

struct ChatSetupModal: View {
    @EnvironmentObject var claudeCodeService: ClaudeCodeService
    @EnvironmentObject var router: PanelRouter
    @Environment(\.snapshotState) private var snapshotState
    @State private var pathError: String?

    private static let notRunnable = "That file can’t be run. Choose the file named claude."

    /// Still looking (the login-shell search takes a moment): don't call it missing yet.
    private var isChecking: Bool {
        claudeCodeService.isDetecting || snapshotState == "agent-setup-checking"
    }

    var body: some View {
        OrtusModal(title: "Agent setup", onClose: { router.modal = nil }) {
            // The whole sheet changes when Claude Code turns up, so the switch can't be missed.
            Group {
                if claudeCodeService.isConfigured {
                    ready.transition(.opacity.combined(with: .scale(scale: 0.94)))
                } else if isChecking {
                    checking.transition(.opacity)
                } else {
                    notFound.transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: claudeCodeService.isConfigured)
        }
        .onAppear {
            if snapshotState == "agent-setup-error" { pathError = Self.notRunnable }
        }
    }

    /// Found: a done screen. "Ready" means Claude Code is on this Mac, not that it's
    /// signed in.
    private var ready: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            OrtusIcon(.check, size: 30)
                .foregroundStyle(OrtusTheme.onStrong)
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous).fill(OrtusTheme.strong))
            VStack(spacing: 4) {
                Text("Your agent is ready")
                    .font(OrtusTheme.Typo.titleSmall)
                    .tracking(-1)
                    .multilineTextAlignment(.center)
                HStack(spacing: 2) {
                    Text(((claudeCodeService.resolvedBinaryPath ?? "") as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(OrtusTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Change", action: chooseClaude)
                        .buttonStyle(OrtusGhostButtonStyle())
                        .help("Choose another Claude Code")
                }
            }
            if let pathError { problemLine(pathError) }
            Button("Start", action: start)
                .buttonStyle(OrtusPrimaryButtonStyle(fullWidth: true))
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
    }

    /// Closes the popup and puts the cursor in the Agent tab's text box.
    private func start() {
        router.modal = nil
        router.requestedTab = 2
        router.focusChatInput = true
    }

    /// Not found: the headline, then two equal ways forward (get it, or point Ortus at
    /// the copy you have), then a quiet check for after installing.
    private var notFound: some View {
        VStack(spacing: OrtusTheme.spacingMD) {
            VStack(spacing: 10) {
                OrtusProblemIcon(size: 28)
                Text("Claude Code was not found on this Mac.")
                    .font(OrtusTheme.Typo.cardTitle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Small, so both labels fit side by side in the sheet.
            HStack(spacing: OrtusTheme.spacingSM) {
                Link(destination: URL(string: "https://docs.claude.com/claude-code")!) { Text("Install Claude Code") }
                    .buttonStyle(OrtusSecondaryButtonStyle(size: .small, fullWidth: true))
                Button("Find my Claude Code", action: chooseClaude)
                    .buttonStyle(OrtusSecondaryButtonStyle(size: .small, fullWidth: true))
            }
            if let pathError { problemLine(pathError) }
            Button {
                pathError = nil
                claudeCodeService.redetect()
            } label: {
                HStack(spacing: 7) {
                    OrtusIcon(.reload, size: 13)
                    Text("Check again")
                }
            }
            .buttonStyle(OrtusSecondaryButtonStyle(size: .small))
        }
        .frame(maxWidth: .infinity)
    }

    private var checking: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Looking for Claude Code…").font(OrtusTheme.Typo.callout).foregroundStyle(OrtusTheme.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func problemLine(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            OrtusProblemIcon(size: 16)
            Text(message).font(OrtusTheme.Typo.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The file picker behind "Find my Claude Code" and "Change". Hidden folders show,
    /// since the installer puts claude in ~/.local/bin.
    private func chooseClaude() {
        let panel = NSOpenPanel()
        panel.title = "Find Claude Code"
        panel.message = "Choose the file named claude."
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        // Keep ~/.local/bin/claude as chosen, not the version folder it links to: that
        // changes every time Claude Code updates itself.
        panel.resolvesAliases = false
        let home = FileManager.default.homeDirectoryForCurrentUser
        let localBin = home.appendingPathComponent(".local/bin", isDirectory: true)
        panel.directoryURL = claudeCodeService.resolvedBinaryPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
            ?? (FileManager.default.fileExists(atPath: localBin.path) ? localBin : home)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard ClaudeLocation.isRunnable(url.path) else {
                pathError = Self.notRunnable
                return
            }
            pathError = nil
            claudeCodeService.claudeBinaryPath = url.path
            claudeCodeService.redetect()
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
