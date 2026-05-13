import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var focusManager: FocusManager
    @EnvironmentObject var slackOAuthService: SlackOAuthService
    @EnvironmentObject var claudeCodeService: ClaudeCodeService

    @State private var slackClientId: String = ""
    @State private var slackClientSecret: String = ""
    @State private var showSlackSetup = false
    @State private var launchAtLogin = false
    @State private var versionTapCount = 0
    @State private var showEmergencyConfirm = false
    @State private var showSlackPreview = false
    @State private var taglineIndex = 0

    /// Easter egg: tapping "Ortus" cycles through a few sunrise-themed lines.
    /// Index 0 is the default tagline so first launch shows nothing unusual.
    private let taglines = [
        "Focus mode for deep work",
        "Ortus, n. — the rising of the sun",
        "First light. First task.",
        "Carpe lucem.",
        "Wake. Work. Wonder."
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingLG) {
                aiChatCard
                slackStatusCard
                preferencesCard

                if focusManager.isInFocus && !focusManager.isInGracePeriod {
                    emergencyCard
                }

                aboutCard
            }
            .padding(OrtusTheme.spacingMD)
        }
        .toggleStyle(.switch)
        .tint(OrtusTheme.accent)
        .onAppear {
            slackClientId = KeychainService.load(.slackClientId) ?? ""
            slackClientSecret = KeychainService.load(.slackClientSecret) ?? ""
        }
    }

    // MARK: - AI Chat

    private var aiChatCard: some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
            OrtusSectionHeader(title: "AI chat")

            HStack(spacing: OrtusTheme.spacingSM) {
                Image(systemName: claudeCodeService.isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(claudeCodeService.isConfigured ? OrtusTheme.success : OrtusTheme.warning)
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 2) {
                    Text(claudeCodeService.isConfigured ? "Claude Code detected" : "Claude Code not found")
                        .font(OrtusTheme.Typo.bodyMedium)
                        .foregroundStyle(.primary)
                    Text(claudeCodeService.resolvedBinaryPath ?? "Install at docs.claude.com/claude-code")
                        .font(OrtusTheme.Typo.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            Text("Chat runs your local Claude Code and its Slack MCP. No API key needed.")
                .font(OrtusTheme.Typo.caption)
                .foregroundStyle(OrtusTheme.textMuted)

            VStack(alignment: .leading, spacing: OrtusTheme.spacingXS) {
                Text("Custom binary path (optional)")
                    .font(OrtusTheme.Typo.meta)
                    .foregroundStyle(.secondary)
                TextField("/opt/homebrew/bin/claude", text: $claudeCodeService.claudeBinaryPath)
                    .textFieldStyle(OrtusTextFieldStyle())
            }
        }
        .ortusCard()
    }

    // MARK: - Slack Status

    private var slackStatusCard: some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
            OrtusSectionHeader(title: "Slack status")

            Toggle("Update Slack status during focus", isOn: $focusManager.slackStatusEnabled)
                .font(OrtusTheme.Typo.bodyMedium)
                .disabled(!slackOAuthService.isConnected)

            if focusManager.slackStatusEnabled && slackOAuthService.isConnected {
                statusComposer
                Toggle("Snooze notifications (Do Not Disturb)", isOn: $focusManager.slackDndEnabled)
                    .font(OrtusTheme.Typo.bodyMedium)
                previewDisclosure
            }

            connectionRow
        }
        .ortusCard()
    }

    private func labeledField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingXS) {
            Text(label)
                .font(OrtusTheme.Typo.meta)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(OrtusTextFieldStyle())
        }
    }

    /// Slack-style status composer: emoji picker button + status text field on one row,
    /// matching Slack's own "Set a status" UI. Replaces the old two stacked text fields.
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

    /// Progressive disclosure: the preview stays hidden by default so the section
    /// reads compact at a glance, but is one click away when the user wants to
    /// see how teammates will perceive their status.
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

    @ViewBuilder
    private var connectionRow: some View {
        if slackOAuthService.isConnected {
            HStack(spacing: OrtusTheme.spacingSM) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(OrtusTheme.success)
                    .font(.system(size: 14))
                Text("Connected to \(slackOAuthService.teamName ?? "Slack")")
                    .font(OrtusTheme.Typo.body)
                    .foregroundStyle(.primary)
                Spacer()
                Button("Disconnect") {
                    slackOAuthService.disconnect()
                }
                .buttonStyle(OrtusDestructiveButtonStyle())
            }
        } else {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                HStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text("Slack isn't connected")
                        .font(OrtusTheme.Typo.bodyMedium)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showSlackSetup.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showSlackSetup ? "Hide" : "Set up")
                            Image(systemName: showSlackSetup ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(OrtusTheme.Typo.button)
                        .foregroundStyle(OrtusTheme.accent)
                    }
                    .buttonStyle(.plain)
                }

                if showSlackSetup {
                    setupForm
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
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

    @State private var redirectCopied = false
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

    // MARK: - Preferences

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
            OrtusSectionHeader(title: "Preferences")
            Toggle("Relaunch Slack when focus ends", isOn: $focusManager.relaunchSlackOnEnd)
                .font(OrtusTheme.Typo.bodyMedium)
            Toggle("Show notifications", isOn: $focusManager.showNotifications)
                .font(OrtusTheme.Typo.bodyMedium)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .font(OrtusTheme.Typo.bodyMedium)
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }
        }
        .ortusCard()
    }

    // MARK: - Emergency

    private var emergencyCard: some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
            OrtusSectionHeader(title: "Emergency")
            if focusManager.canUseEmergencyEnd {
                if showEmergencyConfirm {
                    Text("Slack stays paused until the original end time. You can use this once per week.")
                        .font(OrtusTheme.Typo.caption)
                        .foregroundStyle(OrtusTheme.warning)

                    HStack {
                        Button("Confirm end") {
                            focusManager.emergencyEndFocusSession()
                            showEmergencyConfirm = false
                        }
                        .buttonStyle(OrtusGhostButtonStyle())
                        .foregroundStyle(OrtusTheme.warning)

                        Button("Cancel") {
                            showEmergencyConfirm = false
                        }
                        .buttonStyle(OrtusGhostButtonStyle())
                    }
                } else {
                    Text("Use only for genuine emergencies. Limited to once per week.")
                        .font(OrtusTheme.Typo.caption)
                        .foregroundStyle(.secondary)

                    Button("Emergency end") {
                        showEmergencyConfirm = true
                    }
                    .buttonStyle(OrtusGhostButtonStyle())
                    .foregroundStyle(OrtusTheme.warning)
                }
            } else if let nextDate = focusManager.nextEmergencyAvailableDate {
                Text("Emergency end unavailable until \(nextDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(OrtusTheme.Typo.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .ortusCard()
    }

    // MARK: - About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
            OrtusSectionHeader(title: "About")

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
                            Text("v1.0")
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

                    if focusManager.isInFocus || focusManager.isEmergencyEnded {
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
                .disabled(focusManager.isInFocus || focusManager.isEmergencyEnded)
            }
        }
        .ortusCard()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !enabled
        }
    }
}
