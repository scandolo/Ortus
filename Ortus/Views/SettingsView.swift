import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var focusManager: FocusManager
    @EnvironmentObject var slackOAuthService: SlackOAuthService
    @EnvironmentObject var claudeCodeService: ClaudeCodeService
    @EnvironmentObject var updateService: UpdateService

    @State private var slackClientId: String = ""
    @State private var slackClientSecret: String = ""
    @State private var showSlackSetup = false
    @State private var launchAtLogin = false
    @State private var versionTapCount = 0
    @State private var showEmergencyConfirm = false
    @State private var showSlackPreview = false
    @State private var taglineIndex = 0
    @State private var redirectCopied = false

    /// Easter egg: tapping "Ortus" cycles through a few sunrise-themed lines.
    /// Index 0 is the default tagline so first launch shows nothing unusual.
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
                Text("SETTINGS")
                    .font(OrtusTheme.Typo.section)
                    .tracking(2.2)
                    .foregroundStyle(OrtusTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, OrtusTheme.spacingXS)

                slackSection
                aiChatSection
                generalSection

                if focusManager.isInFocus && !focusManager.isInGracePeriod {
                    emergencySection
                }

                aboutSection
            }
            .padding(OrtusTheme.spacingMD)
        }
    }

    /// A titled group of rows. The header is the only chrome — rows carry their
    /// own surfaces, so sections read as clean stacks separated by whitespace
    /// (no dividers, per the design guidelines).
    private func section<Content: View>(
        _ title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
            VStack(alignment: .leading, spacing: 4) {
                OrtusSectionHeader(title: title)
                if let description {
                    Text(description)
                        .font(OrtusTheme.Typo.caption)
                        .foregroundStyle(OrtusTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)
            content()
        }
    }

    // MARK: - Slack

    private var slackSection: some View {
        section(
            "Slack status",
            description: "Connect the Slack API so Ortus can set your status and turn on Do Not Disturb while you focus."
        ) {
            if slackOAuthService.isConnected {
                connectedRow
                OrtusToggleRow(
                    title: "Set status during focus",
                    isOn: $focusManager.slackStatusEnabled
                )
                OrtusToggleRow(
                    title: "Snooze notifications (Do Not Disturb)",
                    isOn: $focusManager.slackDndEnabled
                )
                if focusManager.slackStatusEnabled {
                    VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                        statusComposer
                        previewDisclosure
                    }
                    .ortusRow()
                }
            } else {
                connectRow
                if showSlackSetup {
                    setupForm
                        .ortusRow()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var connectedRow: some View {
        HStack(spacing: OrtusTheme.spacingSM) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(OrtusTheme.success)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected")
                    .font(OrtusTheme.Typo.bodyMedium)
                Text(slackOAuthService.teamName ?? "Slack")
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Disconnect") { slackOAuthService.disconnect() }
                .buttonStyle(OrtusDestructiveButtonStyle())
        }
        .ortusRow()
    }

    private var connectRow: some View {
        HStack(spacing: OrtusTheme.spacingSM) {
            Image(systemName: "link.badge.plus")
                .foregroundStyle(.secondary)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text("Not connected")
                    .font(OrtusTheme.Typo.bodyMedium)
                Text("Connect your Slack workspace")
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(showSlackSetup ? "Hide" : "Set up") {
                if !showSlackSetup { loadSlackCredentialsIfNeeded() }
                withAnimation(.easeOut(duration: 0.2)) { showSlackSetup.toggle() }
            }
            .buttonStyle(OrtusSecondaryButtonStyle())
        }
        .ortusRow()
    }

    /// Lazy keychain read: only fetch the saved Slack credentials when the user
    /// actually opens the setup form. Pre-loading on view appearance was firing
    /// a keychain prompt every time Settings was opened.
    private func loadSlackCredentialsIfNeeded() {
        if slackClientId.isEmpty {
            slackClientId = KeychainService.load(.slackClientId) ?? ""
        }
        if slackClientSecret.isEmpty {
            slackClientSecret = KeychainService.load(.slackClientSecret) ?? ""
        }
    }

    /// Slack-style status composer: emoji picker button + status text field on one row.
    private var statusComposer: some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingXS) {
            Text("Status")
                .font(OrtusTheme.Typo.meta)
                .foregroundStyle(.secondary)
            HStack(spacing: OrtusTheme.spacingSM) {
                EmojiPickerButton(code: $focusManager.slackStatusEmoji)
                TextField("Ortus mode", text: $focusManager.slackStatusText)
                    .textFieldStyle(OrtusTextFieldStyle())
            }
        }
    }

    /// Progressive disclosure: the preview stays hidden by default so the row
    /// reads compact, but is one click away when the user wants to see it.
    private var previewDisclosure: some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showSlackPreview.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showSlackPreview ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(showSlackPreview ? "Hide preview" : "Preview in Slack")
                }
                .font(OrtusTheme.Typo.caption)
                .foregroundStyle(OrtusTheme.accent)
            }
            .buttonStyle(.plain)

            if showSlackPreview {
                SlackStatusPreview(
                    statusText: focusManager.slackStatusText,
                    emojiCode: focusManager.slackStatusEmoji,
                    userName: NSFullUserName().isEmpty ? "You" : NSFullUserName(),
                    dndEnabled: focusManager.slackDndEnabled
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var setupForm: some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
            Text("Status updates use a Slack app you own. Three steps:")
                .font(OrtusTheme.Typo.caption)
                .foregroundStyle(OrtusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                setupStep(1, "Create a Slack app at api.slack.com/apps")
                setupStep(2, "In OAuth & Permissions → Redirect URLs, add:")
                redirectURIChip
                setupStep(3, "Copy the Client ID + Client Secret from Basic Information below.")
            }

            Link(destination: URL(string: "https://api.slack.com/apps?new_app=1")!) {
                HStack(spacing: 4) {
                    Text("Open Slack app setup")
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(OrtusTheme.Typo.button)
            }
            .foregroundStyle(OrtusTheme.accent)

            TextField("Client ID", text: $slackClientId)
                .textFieldStyle(OrtusTextFieldStyle())
            SecureField("Client Secret", text: $slackClientSecret)
                .textFieldStyle(OrtusTextFieldStyle())

            HStack {
                Spacer()
                Button("Connect Slack") {
                    persistCredentials()
                    slackOAuthService.startOAuthFlow()
                }
                .buttonStyle(OrtusPrimaryButtonStyle())
                .disabled(slackClientId.isEmpty || slackClientSecret.isEmpty)
            }

            if slackOAuthService.isAuthenticating {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(OrtusTheme.accent)
                    Text("Waiting for Slack authorization…")
                        .font(OrtusTheme.Typo.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = slackOAuthService.error {
                Text(error)
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(OrtusTheme.danger)
            }
        }
    }

    private func setupStep(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(n).")
                .font(OrtusTheme.Typo.caption)
                .foregroundStyle(OrtusTheme.accent)
                .monospacedDigit()
            Text(text)
                .font(OrtusTheme.Typo.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var redirectURIChip: some View {
        HStack(spacing: 6) {
            Text(SlackOAuthService.callbackURL)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(SlackOAuthService.callbackURL, forType: .string)
                redirectCopied = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    redirectCopied = false
                }
            } label: {
                Image(systemName: redirectCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(redirectCopied ? OrtusTheme.success : OrtusTheme.accent)
            }
            .buttonStyle(.plain)
            .help("Copy redirect URL")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusSM, style: .continuous).fill(OrtusTheme.inputSurface))
        .overlay(RoundedRectangle(cornerRadius: OrtusTheme.radiusSM, style: .continuous).strokeBorder(OrtusTheme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: OrtusTheme.radiusSM, style: .continuous))
    }

    private func persistCredentials() {
        if !slackClientId.isEmpty {
            try? KeychainService.save(slackClientId, for: .slackClientId)
        }
        if !slackClientSecret.isEmpty {
            try? KeychainService.save(slackClientSecret, for: .slackClientSecret)
        }
    }

    // MARK: - AI Chat

    private var aiChatSection: some View {
        section("AI chat") {
            claudeStatusRow
            if !claudeCodeService.isConfigured {
                binaryPathRow
            }
        }
        .onAppear { claudeCodeService.detectIfNeeded() }
    }

    private var claudeStatusRow: some View {
        HStack(spacing: OrtusTheme.spacingSM) {
            Image(systemName: claudeCodeService.isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(claudeCodeService.isConfigured ? OrtusTheme.success : OrtusTheme.warning)
                .font(.system(size: 16))
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(claudeCodeService.isConfigured ? "Claude Code detected" : "Claude Code not found")
                    .font(OrtusTheme.Typo.bodyMedium)
                Text(claudeCodeService.resolvedBinaryPath ?? "Install at docs.claude.com/claude-code")
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if !claudeCodeService.isConfigured {
                Button("Re-check") { claudeCodeService.redetect() }
                    .buttonStyle(OrtusSecondaryButtonStyle())
            }
        }
        .ortusRow()
    }

    private var binaryPathRow: some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingXS) {
            Text("Custom binary path")
                .font(OrtusTheme.Typo.meta)
                .foregroundStyle(.secondary)
            TextField("/opt/homebrew/bin/claude", text: $claudeCodeService.claudeBinaryPath)
                .textFieldStyle(OrtusTextFieldStyle())
            Text("If you just installed it, tap Re-check. Or run `which claude` in Terminal and paste the path.")
                .font(OrtusTheme.Typo.caption)
                .foregroundStyle(OrtusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ortusRow()
    }

    // MARK: - General

    private var generalSection: some View {
        section("General") {
            OrtusToggleRow(
                title: "Launch at login",
                isOn: $launchAtLogin
            )
            .onChange(of: launchAtLogin) { _, newValue in
                setLaunchAtLogin(newValue)
            }
        }
        // Sync the toggle with macOS's real SMAppService registration each time
        // Settings appears — without this the toggle reads off on first open even
        // when the app is registered.
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Swallow; the re-sync below pulls the actual state from macOS.
        }
        let actual = SMAppService.mainApp.status == .enabled
        if launchAtLogin != actual {
            launchAtLogin = actual
        }
    }

    // MARK: - Emergency

    private var emergencySection: some View {
        section("Emergency") {
            Group {
                if focusManager.canUseEmergencyEnd {
                    if showEmergencyConfirm {
                        HStack(alignment: .center, spacing: OrtusTheme.spacingMD) {
                            Text("Ends focus now and lets you back into Slack. Once per week.")
                                .font(OrtusTheme.Typo.caption)
                                .foregroundStyle(OrtusTheme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("Cancel") { showEmergencyConfirm = false }
                                .buttonStyle(OrtusGhostButtonStyle())
                            Button("Confirm end") {
                                focusManager.emergencyEndFocusSession()
                                showEmergencyConfirm = false
                            }
                            .buttonStyle(OrtusDestructiveButtonStyle())
                        }
                    } else {
                        HStack(alignment: .center, spacing: OrtusTheme.spacingMD) {
                            Text("Use only for genuine emergencies. Limited to once per week.")
                                .font(OrtusTheme.Typo.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("Emergency end") { showEmergencyConfirm = true }
                                .buttonStyle(OrtusDestructiveButtonStyle())
                        }
                    }
                } else if let nextDate = focusManager.nextEmergencyAvailableDate {
                    Text("Emergency end unavailable until \(nextDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(OrtusTheme.Typo.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .ortusRow()
        }
    }

    // MARK: - About

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var aboutSection: some View {
        section("About") {
            updateRow
            aboutRow
        }
    }

    @ViewBuilder
    private var updateRow: some View {
        switch updateService.state {
        case let .available(version):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: OrtusTheme.spacingSM) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(OrtusTheme.accent)
                        .font(.system(size: 16))
                        .symbolRenderingMode(.hierarchical)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update available")
                            .font(OrtusTheme.Typo.bodyMedium)
                        Text("Version \(version)")
                            .font(OrtusTheme.Typo.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Restart & update") {
                        Task { await updateService.downloadAndInstall(isInFocus: focusManager.isInFocus) }
                    }
                    .buttonStyle(OrtusPrimaryButtonStyle())
                    .disabled(focusManager.isInFocus)
                }
                if focusManager.isInFocus {
                    Text("Finish your focus session to update — Ortus restarts to apply it.")
                        .font(OrtusTheme.Typo.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .ortusRow()

        case .downloading:
            HStack(spacing: OrtusTheme.spacingSM) {
                ProgressView().scaleEffect(0.7).tint(OrtusTheme.accent)
                Text("Downloading update — Ortus will restart…")
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .ortusRow()

        case let .failed(message):
            HStack(spacing: OrtusTheme.spacingSM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(OrtusTheme.danger)
                    .symbolRenderingMode(.hierarchical)
                Text(message)
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .ortusRow()

        case .idle, .checking, .upToDate:
            EmptyView()
        }
    }

    private var aboutRow: some View {
        HStack(alignment: .center, spacing: OrtusTheme.spacingMD) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            taglineIndex = (taglineIndex + 1) % taglines.count
                        }
                    } label: {
                        Text("Ortus")
                            .font(OrtusTheme.Typo.headline)
                    }
                    .buttonStyle(.plain)

                    Button {
                        versionTapCount += 1
                        if versionTapCount >= 7 {
                            focusManager.developerModeEnabled.toggle()
                            versionTapCount = 0
                        }
                    } label: {
                        Text("v\(appVersion)")
                            .font(OrtusTheme.Typo.meta)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text(taglines[taglineIndex])
                    .font(OrtusTheme.Typo.caption)
                    .italic(taglineIndex > 0)
                    .foregroundStyle(.secondary)

                if focusManager.developerModeEnabled {
                    Text("Developer mode active")
                        .font(OrtusTheme.Typo.meta)
                        .foregroundStyle(OrtusTheme.warning)
                }

                if focusManager.isInFocus {
                    Text("Cannot quit during focus")
                        .font(OrtusTheme.Typo.meta)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button("Quit Ortus") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(OrtusDestructiveButtonStyle())
            .disabled(focusManager.isInFocus)
        }
        .ortusRow()
    }
}
