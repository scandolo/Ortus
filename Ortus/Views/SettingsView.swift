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

    @State private var launchAtLogin = false
    @State private var versionTapCount = 0
    @State private var showEmergencyConfirm = false
    @State private var showSlackPreview = false
    @State private var taglineIndex = 0
    @AppStorage("genZMode") private var genZ = false

    /// Easter egg: tapping "Ortus" cycles through a few sunrise-themed lines.
    private let taglines = [
        "Focus mode for deep work",
        "Ortus, n. the rising of the sun",
        "First light. First task.",
        "Carpe lucem.",
        "Wake. Work. Wonder."
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingLG) {
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
                        Image(systemName: "power")
                    } trailing: {
                        toggle($launchAtLogin)
                    }
                    OrtusGroupDivider()
                    OrtusListRow(title: "Gen Z mode", subtitle: genZ ? "it’s giving focus" : "Rewrites Ortus in Gen Z") {
                        Image(systemName: "sparkles")
                    } trailing: {
                        toggle($genZ)
                    }
                    if !BuildProfile.isPreview, let update = updateRow {
                        OrtusGroupDivider()
                        update
                    }
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
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
            OrtusSectionHeader(title: title).padding(.horizontal, 4)
            OrtusGroup { content() }
        }
    }

    private func toggle(_ isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(OrtusTheme.accent)
    }

    // MARK: - Connections

    private var slackRow: some View {
        OrtusListRow(title: "Slack status",
                     subtitle: slackOAuthService.isConnected ? "Connected to \(slackOAuthService.teamName ?? "Slack")" : "Status and Do Not Disturb while you focus") {
            BrandGlyph(id: "slack")
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
            Image(systemName: "sparkles")
        } trailing: {
            Button("Configure…") { router.modal = .chatSetup }.buttonStyle(OrtusRowButtonStyle())
        }
    }

    private var slackStatusSection: some View {
        section("Slack status") {
            OrtusListRow(title: "Set my status") { Image(systemName: "text.bubble") } trailing: { toggle($focusManager.slackStatusEnabled) }
            if focusManager.slackStatusEnabled {
                OrtusGroupDivider()
                HStack(spacing: 12) {
                    EmojiPickerButton(code: $focusManager.slackStatusEmoji).frame(width: 22)
                    TextField("Ortus mode", text: $focusManager.slackStatusText).textFieldStyle(.plain).font(OrtusTheme.Typo.body)
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
            OrtusListRow(title: "Do Not Disturb") { Image(systemName: "moon") } trailing: { toggle($focusManager.slackDndEnabled) }
        }
    }

    // MARK: - Emergency

    private var emergencyRow: some View {
        OrtusListRow(title: "End focus early",
                     subtitle: focusManager.canUseEmergencyEnd
                        ? (showEmergencyConfirm ? "Unlocks everything now. Once per week." : "For real emergencies, once per week")
                        : "Available again \(focusManager.nextEmergencyAvailableDate?.formatted(date: .abbreviated, time: .shortened) ?? "next week")") {
            Image(systemName: "exclamationmark.octagon")
        } trailing: {
            if focusManager.canUseEmergencyEnd {
                if showEmergencyConfirm {
                    HStack(spacing: 6) {
                        Button("Cancel") { showEmergencyConfirm = false }.buttonStyle(OrtusRowButtonStyle())
                        Button("End now") { focusManager.emergencyEndFocusSession(); showEmergencyConfirm = false }
                            .buttonStyle(OrtusRowButtonStyle(role: .destructive))
                    }
                } else {
                    Button("End early") { showEmergencyConfirm = true }.buttonStyle(OrtusRowButtonStyle(role: .destructive))
                }
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
            Image(systemName: "sunrise.fill").foregroundStyle(OrtusTheme.accent)
                .symbolEffect(.bounce, value: versionTapCount)
                .onTapGesture {
                    taglineIndex = (taglineIndex + 1) % taglines.count
                    versionTapCount += 1
                    if versionTapCount >= 7 { focusManager.developerModeEnabled.toggle(); versionTapCount = 0 }
                }
        } trailing: {
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(OrtusRowButtonStyle(role: .destructive))
                .disabled(focusManager.isInFocus)
        }
    }

    private var updateRow: AnyView? {
        switch updateService.state {
        case let .available(version):
            return AnyView(OrtusListRow(title: "Update available",
                                        subtitle: !updateService.installsAfterFocus ? "Version \(version)"
                                            : focusManager.isInFocus ? "Version \(version) · installs an hour after this session"
                                            : "Version \(version) · installs within the hour") {
                Image(systemName: "arrow.down.circle")
            } trailing: {
                if focusManager.isInFocus && updateService.installsAfterFocus {
                    EmptyView()
                } else if focusManager.isInFocus {
                    Button("Update after session") { updateService.installAfterFocus(focusManager) }
                        .buttonStyle(OrtusRowButtonStyle())
                } else {
                    Button("Restart & update") { Task { await updateService.downloadAndInstall(isInFocus: false) } }
                        .buttonStyle(OrtusRowButtonStyle())
                }
            })
        case .downloading:
            return AnyView(OrtusListRow(title: "Updating", subtitle: "Ortus will restart") {
                ProgressView().controlSize(.small)
            } trailing: { EmptyView() })
        case let .failed(message):
            return AnyView(OrtusListRow(title: "Update failed", subtitle: message) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(OrtusTheme.danger)
            } trailing: { EmptyView() })
        case .idle, .checking, .upToDate:
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
                Text(claudeCodeService.isConfigured ? "Claude Code detected on this Mac" : "Claude Code not found")
                    .font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
                VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                    Text("Claude Code location").font(OrtusTheme.Typo.bodyMedium)
                    TextField(claudeCodeService.resolvedBinaryPath ?? "/opt/homebrew/bin/claude", text: $binaryPath)
                        .textFieldStyle(OrtusTextFieldStyle())
                        .accessibilityLabel("Claude Code location")
                    Text("Leave empty to detect automatically.")
                        .font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
                }
                if let pathError {
                    Text(pathError).font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !claudeCodeService.isConfigured {
                    Link("Install Claude Code", destination: URL(string: "https://docs.claude.com/claude-code")!)
                        .font(OrtusTheme.Typo.body)
                        .foregroundStyle(OrtusTheme.accentInk)
                }
                HStack {
                    Button("Check again") { applyPath() }.buttonStyle(OrtusRowButtonStyle())
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
                    .font(OrtusTheme.Typo.body).foregroundStyle(OrtusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                OrtusGroup {
                    OrtusStepRow(number: 1, title: "Create a Slack app") {
                        Link("Open Slack", destination: URL(string: "https://api.slack.com/apps?new_app=1")!)
                            .buttonStyle(OrtusRowButtonStyle())
                    }
                    OrtusGroupDivider()
                    OrtusStepRow(number: 2, title: "Add this redirect URL", detail: "OAuth & Permissions → Redirect URLs\n\(SlackOAuthService.callbackURL)") {
                        Button(copied ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(SlackOAuthService.callbackURL, forType: .string)
                            copied = true
                        }
                        .buttonStyle(OrtusRowButtonStyle())
                    }
                    OrtusGroupDivider()
                    OrtusStepRow(number: 3, title: "Paste the Client ID and Secret", detail: "Basic Information → App Credentials") { EmptyView() }
                }
                TextField("Client ID", text: $clientID).textFieldStyle(OrtusTextFieldStyle())
                SecureField("Client Secret", text: $clientSecret).textFieldStyle(OrtusTextFieldStyle())
                if let error = slackOAuthService.error {
                    Text(error).font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if slackOAuthService.isAuthenticating {
                        ProgressView().controlSize(.small)
                        Text("Waiting for Slack…").font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
                    }
                    Spacer()
                    Button("Connect Slack") {
                        try? KeychainService.save(clientID, for: .slackClientId)
                        try? KeychainService.save(clientSecret, for: .slackClientSecret)
                        slackOAuthService.startOAuthFlow()
                    }
                    .buttonStyle(OrtusPrimaryButtonStyle())
                    .disabled(clientID.isEmpty || clientSecret.isEmpty)
                }
            }
        }
        // Read saved credentials only when the form opens, so Settings never triggers a keychain prompt.
        .onAppear {
            clientID = KeychainService.load(.slackClientId) ?? ""
            clientSecret = KeychainService.load(.slackClientSecret) ?? ""
        }
        .onChange(of: slackOAuthService.isConnected) { _, connected in if connected { router.modal = nil } }
    }
}
