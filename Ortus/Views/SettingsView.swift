import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var focusManager: FocusManager
    @EnvironmentObject var slackOAuthService: SlackOAuthService
    @EnvironmentObject var slackService: SlackService

    @State private var claudeAPIKey: String = ""
    @State private var slackClientId: String = ""
    @State private var slackClientSecret: String = ""
    @State private var showingAPIKey = false
    @AppStorage("hasRegisteredLaunchAtLogin") private var hasRegisteredLaunchAtLogin = false
    @State private var launchAtLogin = true
    @State private var versionTapCount = 0
    @State private var showEmergencyConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingLG) {
                // Claude API Key
                OrtusSectionHeader(title: "Claude API")
                VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                    HStack {
                        if showingAPIKey {
                            TextField("sk-ant-...", text: $claudeAPIKey)
                                .textFieldStyle(OrtusTextFieldStyle())
                        } else {
                            SecureField("sk-ant-...", text: $claudeAPIKey)
                                .textFieldStyle(OrtusTextFieldStyle())
                        }
                        Button {
                            showingAPIKey.toggle()
                        } label: {
                            Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Save API key") {
                        if !claudeAPIKey.isEmpty {
                            try? KeychainService.save(claudeAPIKey, for: .claudeAPIKey)
                        }
                    }
                    .buttonStyle(OrtusSecondaryButtonStyle())
                    .disabled(claudeAPIKey.isEmpty)
                }
                .ortusCard()

                // Slack Connection
                OrtusSectionHeader(title: "Slack")
                VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                    if slackOAuthService.isConnected {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(OrtusTheme.success)
                            Text("Connected to \(slackOAuthService.teamName ?? "Slack")")
                                .font(.system(size: 13))
                            Spacer()
                            Button("Disconnect") {
                                slackOAuthService.disconnect()
                            }
                            .buttonStyle(OrtusGhostButtonStyle())
                            .foregroundStyle(OrtusTheme.danger)
                        }
                    } else {
                        Text("Slack app credentials")
                            .font(.system(size: 12))
                            .foregroundStyle(OrtusTheme.textSecondary)

                        TextField("Client ID", text: $slackClientId)
                            .textFieldStyle(OrtusTextFieldStyle())
                        SecureField("Client Secret", text: $slackClientSecret)
                            .textFieldStyle(OrtusTextFieldStyle())

                        HStack {
                            Button("Save credentials") {
                                if !slackClientId.isEmpty {
                                    try? KeychainService.save(slackClientId, for: .slackClientId)
                                }
                                if !slackClientSecret.isEmpty {
                                    try? KeychainService.save(slackClientSecret, for: .slackClientSecret)
                                }
                            }
                            .buttonStyle(OrtusSecondaryButtonStyle())
                            .disabled(slackClientId.isEmpty || slackClientSecret.isEmpty)

                            Spacer()

                            Button("Connect Slack") {
                                if !slackClientId.isEmpty {
                                    try? KeychainService.save(slackClientId, for: .slackClientId)
                                }
                                if !slackClientSecret.isEmpty {
                                    try? KeychainService.save(slackClientSecret, for: .slackClientSecret)
                                }
                                slackOAuthService.startOAuthFlow()
                            }
                            .buttonStyle(OrtusPrimaryButtonStyle())
                            .disabled(slackClientId.isEmpty && slackOAuthService.clientId.isEmpty)
                        }

                        if slackOAuthService.isAuthenticating {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Waiting for Slack authorization...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(OrtusTheme.textSecondary)
                            }
                        }

                        if let error = slackOAuthService.error {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(OrtusTheme.danger)
                        }
                    }
                }
                .ortusCard()

                // Preferences
                OrtusSectionHeader(title: "Preferences")
                VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .font(.system(size: 13))
                        .onChange(of: launchAtLogin) { newValue in
                            setLaunchAtLogin(newValue)
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .ortusCard()

                // Emergency End (only visible during focus)
                if focusManager.isInFocus {
                    OrtusSectionHeader(title: "Emergency")
                    VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                        if focusManager.canUseEmergencyEnd {
                            if showEmergencyConfirm {
                                Text("Slack stays paused until the original end time. You can use this once per week.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(OrtusTheme.warning)

                                HStack {
                                    Button("Confirm end") {
                                        focusManager.emergencyEndFocusSession()
                                        showEmergencyConfirm = false
                                    }
                                    .buttonStyle(OrtusPrimaryButtonStyle())
                                    .tint(OrtusTheme.warning)

                                    Button("Cancel") {
                                        showEmergencyConfirm = false
                                    }
                                    .buttonStyle(OrtusGhostButtonStyle())
                                }
                            } else {
                                Text("Use only for genuine emergencies. Limited to once per week.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(OrtusTheme.textSecondary)

                                Button("Emergency end") {
                                    showEmergencyConfirm = true
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(OrtusTheme.warning)
                                .buttonStyle(.plain)
                            }
                        } else if let nextDate = focusManager.nextEmergencyAvailableDate {
                            Text("Emergency end unavailable until \(nextDate.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 12))
                                .foregroundStyle(OrtusTheme.textSecondary)
                        }
                    }
                    .ortusCard()
                }

                // About
                OrtusSectionHeader(title: "About")
                VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                    HStack {
                        Text("Ortus")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Button {
                            versionTapCount += 1
                            if versionTapCount >= 7 {
                                focusManager.developerModeEnabled.toggle()
                                versionTapCount = 0
                            }
                        } label: {
                            Text("v1.0")
                                .font(.system(size: 12))
                                .foregroundStyle(OrtusTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Focus mode for deep work")
                        .font(.system(size: 12))
                        .foregroundStyle(OrtusTheme.textSecondary)

                    if focusManager.developerModeEnabled {
                        Text("Developer mode active")
                            .font(.system(size: 11))
                            .foregroundStyle(OrtusTheme.warning)
                    }

                    Button("Quit Ortus") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(OrtusGhostButtonStyle())
                    .foregroundStyle(OrtusTheme.danger)
                    .disabled(focusManager.isInFocus || focusManager.isEmergencyEnded)

                    if focusManager.isInFocus || focusManager.isEmergencyEnded {
                        Text("Cannot quit during focus")
                            .font(.system(size: 11))
                            .foregroundStyle(OrtusTheme.textSecondary)
                    }
                }
                .ortusCard()
            }
            .padding(OrtusTheme.spacingMD)
        }
        .onAppear {
            claudeAPIKey = KeychainService.load(.claudeAPIKey) ?? ""
            slackClientId = KeychainService.load(.slackClientId) ?? ""
            slackClientSecret = KeychainService.load(.slackClientSecret) ?? ""

            // On first launch, register for launch-at-login by default
            if !hasRegisteredLaunchAtLogin {
                hasRegisteredLaunchAtLogin = true
                setLaunchAtLogin(true)
            }
        }
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
