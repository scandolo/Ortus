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
                    slackRow
                    OrtusGroupDivider()
                    chatRow
                }

                if slackOAuthService.isConnected { slackStatusSection }

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
            }
            .padding(OrtusTheme.spacingMD)
        }
        .onAppear {
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
                Button("Disconnect") { slackOAuthService.disconnect() }.buttonStyle(OrtusRowButtonStyle(role: .destructive))
            } else {
                Button("Connect") { router.modal = .slackSetup }.buttonStyle(OrtusRowButtonStyle())
            }
        }
    }

    private var chatRow: some View {
        OrtusListRow(title: "Chat", subtitle: claudeCodeService.isConfigured ? "Claude Code detected" : "Claude Code not found") {
            if claudeCodeService.isConfigured { OrtusIcon(.agent, size: 18) } else { OrtusProblemIcon(size: 18) }
        } trailing: {
            Button(claudeCodeService.isConfigured ? "Configure" : "Set up") { router.modal = .chatSetup }.buttonStyle(OrtusRowButtonStyle())
        }
    }

    private var slackStatusSection: some View {
        section("Slack status") {
            OrtusListRow(title: "Set my status") { OrtusIcon(.chat, size: 18) } trailing: { toggle($focusManager.slackStatusEnabled) }
            if focusManager.slackStatusEnabled {
                OrtusGroupDivider()
                HStack(spacing: 14) {
                    EmojiPickerButton(code: $focusManager.slackStatusEmoji).frame(width: 22)
                    TextField("", text: $focusManager.slackStatusText, prompt: Text("Ortus mode").foregroundStyle(OrtusTheme.textMuted))
                        .textFieldStyle(.plain).font(OrtusTheme.Typo.bodyMedium)
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
        OrtusListRow(title: "Send feedback", subtitle: "Bugs and ideas go to support@ortusmode.com") {
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
                Button("Try again") { Task { await updateService.checkForUpdates() } }
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

// MARK: - Chat setup

struct ChatSetupModal: View {
    @EnvironmentObject var claudeCodeService: ClaudeCodeService
    @EnvironmentObject var router: PanelRouter
    @State private var binaryPath = ""
    @State private var initialBinaryPath = ""
    @State private var pathError: String?

    var body: some View {
        OrtusModal(title: "Chat setup", onClose: { router.modal = nil }) {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                HStack(spacing: 8) {
                    if claudeCodeService.isConfigured { OrtusIcon(.check, size: 14) } else { OrtusProblemIcon(size: 16) }
                    Text(claudeCodeService.isConfigured ? "Claude Code found on this Mac" : "Claude Code not found on this Mac")
                        .font(OrtusFont.text(14))
                }
                VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                    Text("Claude Code location").font(OrtusFont.text(14, .bold))
                    TextField("", text: $binaryPath, prompt: Text(claudeCodeService.resolvedBinaryPath ?? "/opt/homebrew/bin/claude").foregroundStyle(OrtusTheme.textMuted))
                        .textFieldStyle(OrtusTextFieldStyle(monospaced: true))
                        .accessibilityLabel("Claude Code location")
                    Text("Leave empty to find it automatically.")
                        .font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
                }
                if let pathError {
                    HStack(alignment: .top, spacing: 8) {
                        OrtusProblemIcon(size: 16)
                        Text(pathError).font(OrtusTheme.Typo.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !claudeCodeService.isConfigured {
                    Link("Install Claude Code", destination: URL(string: "https://docs.claude.com/claude-code")!)
                        .font(OrtusFont.text(14, .bold))
                        .underline()
                        .foregroundStyle(OrtusTheme.text)
                }
                HStack {
                    Button("Check again") { applyPath() }.buttonStyle(OrtusSecondaryButtonStyle())
                    Spacer()
                    Button("Done") {
                        if applyPath() { router.modal = nil }
                    }
                    .buttonStyle(OrtusPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear {
            initialBinaryPath = claudeCodeService.claudeBinaryPath.isEmpty
                ? claudeCodeService.resolvedBinaryPath ?? ""
                : claudeCodeService.claudeBinaryPath
            binaryPath = initialBinaryPath
        }
        .onChange(of: binaryPath) { _, _ in pathError = nil }
    }

    @discardableResult
    private func applyPath() -> Bool {
        let path = (binaryPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard path.isEmpty || (path.hasPrefix("/")
            && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)) else {
            pathError = "No executable found at this location. Check the path or clear it to detect automatically."
            return false
        }
        if path != initialBinaryPath {
            claudeCodeService.claudeBinaryPath = path
            initialBinaryPath = path
        }
        binaryPath = path
        claudeCodeService.redetect()
        return true
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
                SecureField("", text: $clientSecret, prompt: Text("Client Secret").foregroundStyle(OrtusTheme.textMuted)).textFieldStyle(OrtusTextFieldStyle())
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
