import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OrtusCore

/// One list of everything a session blocks. Presets (Gmail, LinkedIn, Slack) show
/// as a single row once added and as quick-add chips until then, so the same
/// thing never appears twice.
struct BlockingTargetsEditor: View {
    @Binding var selection: BlockSelection
    @State private var website = ""
    @State private var inputError: String?

    private var addedPresets: [BlockingPreset] { BlockingPreset.all.filter { selection.fullyContains($0) } }
    private var suggestedPresets: [BlockingPreset] { BlockingPreset.all.filter { !selection.contains($0) } }
    private var otherWebsites: [String] {
        selection.websites.filter { domain in !addedPresets.contains { $0.selection.websites.contains(domain) } }
    }
    private var otherApplications: [BlockedApplication] {
        selection.applications.filter { app in !addedPresets.contains { $0.selection.applications.contains { $0.id == app.id } } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
            ForEach(addedPresets) { preset in
                targetRow(preset.title, icon: Image(systemName: preset.symbol)) { selection.set(preset, enabled: false) }
            }
            ForEach(otherWebsites, id: \.self) { domain in
                targetRow(domain, icon: Image(systemName: "globe")) { selection.websites.removeAll { $0 == domain } }
            }
            ForEach(otherApplications) { app in
                targetRow(app.name, icon: appIcon(app)) { selection.applications.removeAll { $0.id == app.id } }
            }

            HStack(spacing: 6) {
                TextField("Add a website", text: $website)
                    .textFieldStyle(OrtusTextFieldStyle())
                    .onSubmit(addWebsite)
                    .accessibilityLabel("Website domain or URL")
                Button(action: addWebsite) { Image(systemName: "plus") }
                    .buttonStyle(OrtusSecondaryButtonStyle())
                    .disabled(website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add website")
            }

            HStack(spacing: 6) {
                ForEach(suggestedPresets) { preset in
                    Button { selection.set(preset, enabled: true) } label: {
                        Label(preset.title, systemImage: "plus")
                            .font(OrtusTheme.Typo.caption)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color.primary.opacity(0.05)))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(preset.title)")
                }
                Spacer(minLength: 0)
                Button("Add app…", action: chooseApplications)
                    .buttonStyle(OrtusGhostButtonStyle())
            }

            if !selection.applications.isEmpty {
                Text("Apps close when focus starts.")
                    .font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
            }
            if let inputError {
                Text(inputError).font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func targetRow(_ title: String, icon: Image, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            icon.resizable().scaledToFit().frame(width: 16, height: 16).foregroundStyle(OrtusTheme.textMuted)
            Text(title).font(OrtusTheme.Typo.body).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Button(action: remove) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(OrtusTheme.textMuted) }
                .buttonStyle(.plain).frame(width: 24, height: 24).contentShape(Rectangle())
                .accessibilityLabel("Remove \(title)")
        }
        .padding(.vertical, 2)
    }

    private func appIcon(_ app: BlockedApplication) -> Image {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { return Image(systemName: "macwindow") }
        return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
    }

    private func addWebsite() {
        do {
            let domain = try WebsiteDomain.normalize(website)
            selection = .union([selection, BlockSelection(websites: [domain])])
            website = ""; inputError = nil
        } catch { inputError = error.localizedDescription }
    }

    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.title = "Choose apps to block"
        panel.prompt = "Add applications"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.begin { response in
            guard response == .OK else { return }
            var chosen: [BlockedApplication] = []
            for url in panel.urls {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, BlockedApplication.isBlockable(id) else {
                    inputError = "Ortus, Finder, and System Settings stay available so you can manage your Mac."
                    continue
                }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
                chosen.append(BlockedApplication(bundleID: id, name: name))
            }
            selection = .union([selection, BlockSelection(applications: chosen)])
        }
    }
}

/// Browser connection status with the three setup steps one click away.
struct BrowserSetupView: View {
    @ObservedObject var service: WebsiteBlockingService
    @State private var expanded = false
    @Environment(\.snapshotState) private var snapshotState

    private var connected: Bool { !service.connectedBrowsers.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
            HStack(spacing: 10) {
                Image(systemName: connected ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(connected ? OrtusTheme.success : OrtusTheme.warning)
                Text(connected ? "Connected to \(service.connectedBrowsers.joined(separator: ", "))" : "Websites aren’t blocked yet")
                    .font(OrtusTheme.Typo.bodyMedium)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(expanded ? "Done" : (connected ? "Add browser" : "Connect")) { expanded.toggle() }
                    .buttonStyle(OrtusGhostButtonStyle())
            }
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Open your browser’s extensions page") { openButton }
                    step(2, "Turn on Developer mode, then click Load unpacked") { EmptyView() }
                    step(3, "Choose the “\(service.extensionDirectory?.lastPathComponent ?? "Ortus Browser")” folder") {
                        Button("Show folder") { service.revealCompanion() }.buttonStyle(OrtusGhostButtonStyle())
                    }
                }
            }
            if let error = service.setupError ?? service.error ?? service.enforcementError {
                Text(error).font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .ortusRow()
        .onAppear { if snapshotState == "browser-setup" { expanded = true } }
    }

    @ViewBuilder private var openButton: some View {
        let browsers = service.availableBrowsers
        if browsers.count == 1, let browser = browsers.first {
            Button("Open \(browser.name)") { service.openExtensionsPage(browserID: browser.id) }.buttonStyle(OrtusGhostButtonStyle())
        } else if !browsers.isEmpty {
            Menu {
                ForEach(browsers) { browser in Button(browser.name) { service.openExtensionsPage(browserID: browser.id) } }
            } label: {
                Text("Open").font(OrtusTheme.Typo.button).foregroundStyle(OrtusTheme.accentInk)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    private func step<Action: View>(_ number: Int, _ text: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(number)")
                .font(OrtusTheme.Typo.badge).monospacedDigit()
                .frame(width: 20, height: 20)
                .background(Circle().fill(OrtusTheme.accentSoft))
                .foregroundStyle(OrtusTheme.accentInk)
            Text(text).font(OrtusTheme.Typo.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            action()
        }
    }
}
