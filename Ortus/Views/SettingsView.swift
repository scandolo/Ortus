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
    @State private var launchAtLogin = false
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
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-ant-...", text: $claudeAPIKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            showingAPIKey.toggle()
                        } label: {
                            Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Save API Key") {
                        if !claudeAPIKey.isEmpty {
                            try? KeychainService.save(claudeAPIKey, for: .claudeAPIKey)
                        }
                    }
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
                            Spacer()
                            Button("Disconnect") {
                                slackOAuthService.disconnect()
                            }
                            .foregroundStyle(OrtusTheme.destructive)
                        }
                    } else {
                        Text("Slack App Credentials")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("Client ID", text: $slackClientId)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Client Secret", text: $slackClientSecret)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("Save Credentials") {
                                if !slackClientId.isEmpty {
                                    try? KeychainService.save(slackClientId, for: .slackClientId)
                                }
                                if !slackClientSecret.isEmpty {
                                    try? KeychainService.save(slackClientSecret, for: .slackClientSecret)
                                }
                            }
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
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let error = slackOAuthService.error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(OrtusTheme.destructive)
                        }
                    }
                }
                .ortusCard()

                // Preferences
                OrtusSectionHeader(title: "Preferences")
                VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                    Toggle("Relaunch Slack when focus ends", isOn: $focusManager.relaunchSlackOnEnd)
                    Toggle("Show notifications", isOn: $focusManager.showNotifications)
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            setLaunchAtLogin(newValue)
                        }
                }
                .ortusCard()

                // Emergency End (only visible during focus)
                if focusManager.isInFocus {
                    OrtusSectionHeader(title: "Emergency")
                    VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                        if focusManager.canUseEmergencyEnd {
                            Text("Use only for genuine emergencies. Limited to once per week.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Emergency End Focus") {
                                showEmergencyConfirm = true
                            }
                            .font(.caption)
                            .foregroundStyle(OrtusTheme.warning)
                            .buttonStyle(.plain)
                            .alert("Emergency End?", isPresented: $showEmergencyConfirm) {
                                Button("Cancel", role: .cancel) {}
                                Button("End Focus", role: .destructive) {
                                    focusManager.emergencyEndFocusSession()
                                }
                            } message: {
                                Text("This will end focus mode, but Slack will remain blocked until the original end time. You can only do this once per week.")
                            }
                        } else if let nextDate = focusManager.nextEmergencyAvailableDate {
                            Text("Emergency end unavailable until \(nextDate.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .ortusCard()
                }

                // About
                OrtusSectionHeader(title: "About")
                VStack(alignment: .leading, spacing: OrtusTheme.spacingXS) {
                    HStack {
                        Text("Ortus")
                            .font(.headline)
                        Spacer()
                        Button {
                            versionTapCount += 1
                            if versionTapCount >= 7 {
                                focusManager.developerModeEnabled.toggle()
                                versionTapCount = 0
                            }
                        } label: {
                            Text("v1.0")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Focus mode for Slack with AI assistant")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if focusManager.developerModeEnabled {
                        Text("Developer mode active")
                            .font(.caption2)
                            .foregroundStyle(OrtusTheme.warning)
                    }

                    Divider()

                    Button("Quit Ortus") {
                        NSApplication.shared.terminate(nil)
                    }
                    .foregroundStyle(OrtusTheme.destructive)
                    .disabled(focusManager.isInFocus || focusManager.isEmergencyEnded)

                    if focusManager.isInFocus || focusManager.isEmergencyEnded {
                        Text("Cannot quit during focus mode")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
