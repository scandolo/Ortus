import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OrtusCore

// MARK: - Mode picker

/// Shows the chosen mode in one row. Choosing another mode, or building one, is a
/// click away rather than part of the main screen.
struct ModePicker: View {
    @EnvironmentObject var focusManager: FocusManager
    @EnvironmentObject var router: PanelRouter
    @Binding var selection: BlockSelection
    /// False when the picker sits inside another card.
    var boxed = true
    @State private var expanded = false
    @Environment(\.snapshotState) private var snapshotState

    private var current: FocusMode? { focusManager.mode(for: selection) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    ModeGlyphs(selection: selection, cluster: true)
                    VStack(alignment: .leading, spacing: 2) {
                        (Text("Block mode  ").foregroundColor(OrtusTheme.textMuted) + Text(current?.name ?? "Custom"))
                            .font(OrtusTheme.Typo.bodyMedium)
                        Text(selection.summary).font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    // Same capsule as the row actions in Settings, so it has room to breathe.
                    Text(expanded ? "Done" : "Change").font(OrtusTheme.Typo.button).foregroundStyle(.primary)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(OrtusPressableStyle(inset: 6, cornerRadius: 10))
            .accessibilityLabel("Mode: \(current?.name ?? "Custom")")

            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(focusManager.modes) { mode in modeRow(mode) }
                    Button { edit(FocusMode(name: focusManager.nextCustomModeName, blocked: selection)) } label: {
                        Label("New custom mode", systemImage: "plus").font(OrtusTheme.Typo.button).foregroundStyle(OrtusTheme.accentInk)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(OrtusPressableStyle(inset: 4))
                }
                .padding(.top, OrtusTheme.spacingSM)
            }
        }
        .modifier(BoxedCard(boxed: boxed))
        .onAppear { if snapshotState == "modes" { expanded = true } }
    }

    private func modeRow(_ mode: FocusMode) -> some View {
        let isCurrent = mode.blocked == selection
        let select = {
            selection = mode.blocked
            withAnimation(.easeOut(duration: 0.18)) { expanded = false }
        }
        return HStack(spacing: 10) {
            Button(action: select) {
                HStack(spacing: 10) {
                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isCurrent ? OrtusTheme.accentInk : OrtusTheme.textMuted)
                    Text(mode.name).font(OrtusTheme.Typo.body)
                    Spacer(minLength: 4)
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(OrtusPressableStyle(inset: 4))
            if !mode.isBuiltIn {
                Button("Edit") { edit(mode) }.buttonStyle(OrtusGhostButtonStyle())
            }
            Button(action: select) { ModeGlyphs(selection: mode.blocked).scaleEffect(0.85) }
                .buttonStyle(OrtusPressableStyle(inset: 4)).accessibilityHidden(true).focusable(false)
        }
    }

    private func edit(_ mode: FocusMode) {
        router.modal = .modeEditor(mode) { saved in selection = saved.blocked }
    }
}

private struct BoxedCard: ViewModifier {
    let boxed: Bool
    func body(content: Content) -> some View {
        if boxed { content.ortusCard() } else { content }
    }
}

// MARK: - Mode builder

struct ModeEditor: View {
    @EnvironmentObject var focusManager: FocusManager
    @EnvironmentObject var router: PanelRouter
    @State var mode: FocusMode
    let onSave: (FocusMode) -> Void

    private var isExisting: Bool { focusManager.customModes.contains { $0.id == mode.id } }

    var body: some View {
        OrtusModal(title: isExisting ? "Edit mode" : "New mode", onClose: { router.modal = nil }) {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                TextField("Mode name", text: $mode.name).textFieldStyle(OrtusTextFieldStyle())
                BlockingTargetsEditor(selection: $mode.blocked)
                HStack {
                    if isExisting {
                        Button { focusManager.deleteMode(mode); router.modal = nil } label: {
                            Text("Delete").font(OrtusTheme.Typo.button).foregroundStyle(OrtusTheme.danger)
                        }
                        .buttonStyle(OrtusPressableStyle(inset: 4))
                    }
                    Spacer()
                    Button("Save mode") {
                        focusManager.saveMode(mode)
                        onSave(mode)
                        router.modal = nil
                    }
                    .buttonStyle(OrtusPrimaryButtonStyle())
                    .disabled(mode.name.trimmingCharacters(in: .whitespaces).isEmpty || mode.blocked.isEmpty)
                }
            }
        }
    }
}

// MARK: - Targets

/// Everything a mode blocks, one row each, with adding a website or an app as two
/// rows of the same list.
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
        VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
            OrtusGroup {
                ForEach(addedPresets) { preset in
                    targetRow(preset.title) { BrandGlyph(id: preset.id) } remove: { selection.set(preset, enabled: false) }
                    OrtusGroupDivider()
                }
                ForEach(otherWebsites, id: \.self) { domain in
                    targetRow(domain) { BrandGlyph(id: BrandGlyph.websiteID(for: domain) ?? "") } remove: { selection.websites.removeAll { $0 == domain } }
                    OrtusGroupDivider()
                }
                ForEach(otherApplications) { app in
                    targetRow(app.name) { appIcon(app) } remove: { selection.applications.removeAll { $0.id == app.id } }
                    OrtusGroupDivider()
                }
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle").font(.system(size: 15)).foregroundStyle(OrtusTheme.accentInk).frame(width: 22)
                    TextField("Add a website", text: $website)
                        .textFieldStyle(.plain).font(OrtusTheme.Typo.body)
                        .onSubmit(addWebsite)
                        .accessibilityLabel("Website to block")
                    if !website.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add", action: addWebsite).buttonStyle(OrtusRowButtonStyle())
                    }
                }
                .padding(.horizontal, OrtusTheme.spacingMD).padding(.vertical, 11)
                OrtusGroupDivider()
                Button(action: chooseApplications) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle").font(.system(size: 15)).foregroundStyle(OrtusTheme.accentInk).frame(width: 22)
                        Text("Add an app from Applications…").font(OrtusTheme.Typo.body).foregroundStyle(OrtusTheme.accentInk)
                        Spacer()
                    }
                    .padding(.horizontal, OrtusTheme.spacingMD).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(OrtusPressableStyle(cornerRadius: 0))
            }

            if let inputError {
                Text(inputError).font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !selection.applications.isEmpty {
                Text("Apps in this mode close when focus starts.").font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
            }

            if !suggestedPresets.isEmpty {
                VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                    OrtusSectionHeader(title: "Suggestions")
                    FlowLayout {
                        ForEach(suggestedPresets) { preset in
                            Button { selection.set(preset, enabled: true) } label: {
                                HStack(spacing: 6) {
                                    BrandGlyph(id: preset.id, size: 12)
                                    Text(preset.title).font(OrtusTheme.Typo.caption)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(Color.primary.opacity(0.05)))
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(OrtusPressableStyle(cornerRadius: 20))
                            .accessibilityLabel("Add \(preset.title)")
                        }
                    }
                }
            }
        }
    }

    private func targetRow<Icon: View>(_ title: String, @ViewBuilder icon: () -> Icon, remove: @escaping () -> Void) -> some View {
        OrtusListRow(title: title) { icon() } trailing: {
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(OrtusTheme.textMuted)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(OrtusPressableStyle(cornerRadius: 12)).accessibilityLabel("Remove \(title)")
        }
    }

    private func appIcon(_ app: BlockedApplication) -> some View {
        Group {
            if let id = BrandGlyph.applicationID(for: app) {
                BrandGlyph(id: id)
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
            } else {
                Image(systemName: "macwindow")
            }
        }
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

// MARK: - Browser connection

/// One row: is website blocking working? Setup lives in a modal.
struct BrowserStatusRow: View {
    @ObservedObject var service: WebsiteBlockingService
    @EnvironmentObject var router: PanelRouter

    var body: some View {
        let connected = !service.connectedBrowsers.isEmpty
        OrtusListRow(title: "Website blocking",
                     subtitle: connected ? "On in \(service.connectedBrowsers.joined(separator: ", "))" : "Not set up yet") {
            Image(systemName: connected ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .foregroundStyle(connected ? OrtusTheme.success : OrtusTheme.warning)
        } trailing: {
            Button(connected ? "Add browser" : "Set up") { router.modal = .browserSetup }
                .buttonStyle(OrtusRowButtonStyle())
        }
    }
}

/// The three setup steps, shown in a modal.
struct BrowserSetupModal: View {
    @ObservedObject var service: WebsiteBlockingService
    @EnvironmentObject var router: PanelRouter

    var body: some View {
        OrtusModal(title: "Block websites in your browser", onClose: { router.modal = nil }) {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                Text("A one-time setup for each browser profile. Works with Arc, Chrome, Edge and Brave.")
                    .font(OrtusTheme.Typo.body).foregroundStyle(OrtusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                OrtusGroup {
                    OrtusStepRow(number: 1, title: "Open the extensions page") {
                        ForEach(service.availableBrowsers) { browser in
                            Button(browser.name) { service.openExtensionsPage(browserID: browser.id) }.buttonStyle(OrtusRowButtonStyle())
                        }
                    }
                    OrtusGroupDivider()
                    OrtusStepRow(number: 2, title: "Turn on Developer mode, then click Load unpacked") { EmptyView() }
                    OrtusGroupDivider()
                    OrtusStepRow(number: 3, title: "Choose the “\(service.extensionDirectory?.lastPathComponent ?? "Ortus Browser")” folder") {
                        Button("Show folder") { service.revealCompanion() }.buttonStyle(OrtusRowButtonStyle())
                    }
                }
                if let error = service.setupError ?? service.error ?? service.enforcementError {
                    Text(error).font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if !service.connectedBrowsers.isEmpty {
                        Label("Connected to \(service.connectedBrowsers.joined(separator: ", "))", systemImage: "checkmark.circle.fill")
                            .font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.success)
                    }
                    Spacer()
                    Button("Done") { router.modal = nil }.buttonStyle(OrtusPrimaryButtonStyle())
                }
            }
        }
    }

}
