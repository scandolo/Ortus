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
    /// A setup problem that affects this mode, written under the mode row.
    var problem: (message: String, action: () -> Void)? = nil
    @State private var expanded = false
    @Environment(\.snapshotState) private var snapshotState

    private var current: FocusMode? { focusManager.mode(for: selection) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The whole row opens the list, as before; "Change" is its visible handle.
            Button { withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    BlockedStack(items: BlockedItem.all(in: selection), ground: boxed ? OrtusTheme.inset : OrtusTheme.cardSurface, size: 26)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Block: \(current?.name ?? "Custom")").font(OrtusFont.text(14, .bold)).lineLimit(2)
                        Text(BlockedItem.countLabel(for: selection)).font(OrtusTheme.Typo.meta).foregroundStyle(OrtusTheme.textMuted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(expanded ? "Done" : "Change")
                        .font(OrtusTheme.Typo.buttonSmall).foregroundStyle(OrtusTheme.text)
                        .padding(.horizontal, 12).frame(minHeight: OrtusTheme.controlHeightSM)
                        .overlay(RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous).strokeBorder(OrtusTheme.text, lineWidth: 2))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(OrtusPressableStyle(inset: 6, cornerRadius: 12))
            .accessibilityLabel(expanded ? "Done choosing a mode" : "Mode: \(current?.name ?? "Custom"), \(BlockedItem.countLabel(for: selection)). Change")

            if let problem {
                OrtusProblemNote(message: problem.message, action: problem.action)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(focusManager.modes) { mode in modeRow(mode) }
                    Button { edit(FocusMode(name: focusManager.nextCustomModeName, blocked: selection)) } label: {
                        HStack(spacing: 10) {
                            OrtusIcon(.plus, size: 14)
                            Text("New custom mode").font(OrtusFont.text(14, .bold))
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(OrtusPressableStyle(inset: 4))
                }
            }
        }
        .modifier(BoxedCard(boxed: boxed))
        .onAppear {
            if snapshotState == "modes" || snapshotState == "schedule-modes" { expanded = true }
            if snapshotState == "mode-edit" || snapshotState == "mode-delete", let current, !current.isBuiltIn { edit(current) }
        }
    }

    private func modeRow(_ mode: FocusMode) -> some View {
        // Only the first mode with this list, as in the row above, even if an older
        // version saved two modes with the same list.
        let isCurrent = mode.id == current?.id
        let select = {
            selection = mode.blocked
            withAnimation(.easeOut(duration: 0.18)) { expanded = false }
        }
        return HStack(spacing: 12) {
            Button(action: select) {
                HStack(spacing: 12) {
                    // One choice, as in a macOS menu: a check by the chosen mode, nothing by the rest.
                    Color.clear.frame(width: 20, height: 20)
                        .overlay { if isCurrent { OrtusIcon(.check, size: 14) } }
                    Text(mode.name).font(isCurrent ? OrtusFont.text(15, .bold) : OrtusTheme.Typo.headline)
                    Spacer(minLength: 4)
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(OrtusPressableStyle(inset: 4))
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            if !mode.isBuiltIn {
                Button("Edit") { edit(mode) }.buttonStyle(OrtusGhostButtonStyle())
            }
            Button(action: select) { ModeGlyphs(selection: mode.blocked) }
                .buttonStyle(OrtusPressableStyle(inset: 4)).accessibilityHidden(true).focusable(false)
        }
    }

    private func edit(_ mode: FocusMode) {
        router.modal = .modeEditor(mode) { saved in selection = saved.blocked }
    }
}

/// A mode picker on its own (in a schedule) sits in a bone box inside the card.
private struct BoxedCard: ViewModifier {
    let boxed: Bool
    func body(content: Content) -> some View {
        if boxed {
            content.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: OrtusTheme.radiusMD, style: .continuous).fill(OrtusTheme.inset))
        } else { content }
    }
}

// MARK: - Mode builder

struct ModeEditor: View {
    @EnvironmentObject var focusManager: FocusManager
    @EnvironmentObject var router: PanelRouter
    @State var mode: FocusMode
    let onSave: (FocusMode) -> Void
    @State private var confirmingDelete = false
    @Environment(\.snapshotState) private var snapshotState

    /// The mode as saved, before any edits in this sheet.
    private var saved: FocusMode? { focusManager.customModes.first { $0.id == mode.id } }
    private var isExisting: Bool { saved != nil }
    /// A mode that already blocks exactly this list. Saving would make a copy of it.
    private var duplicate: FocusMode? { FocusMode.duplicate(of: mode, in: focusManager.modes) }

    var body: some View {
        Group {
            if confirmingDelete, let saved {
                // Replaces the editor, so Cancel goes back to it with any edits kept.
                OrtusAlert(title: "Delete \(saved.name)?", message: "Schedules that use it keep their apps and sites.",
                           cancel: "Cancel", confirm: "Delete", onCancel: { confirmingDelete = false }) {
                    focusManager.deleteMode(saved)
                    router.modal = nil
                }
            } else {
                editor
            }
        }
        .onAppear { if snapshotState == "mode-delete" { confirmingDelete = true } }
    }

    private var editor: some View {
        OrtusModal(title: isExisting ? "Edit mode" : "New mode", largeTitle: true, onClose: { router.modal = nil }) {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                TextField("Mode name", text: $mode.name).textFieldStyle(OrtusTextFieldStyle())
                BlockingTargetsEditor(selection: $mode.blocked)
                HStack {
                    if isExisting {
                        Button("Delete mode") { confirmingDelete = true }
                            .buttonStyle(OrtusGhostButtonStyle())
                    }
                    Spacer()
                    Button(isExisting ? "Save mode" : "Create mode") {
                        focusManager.saveMode(mode)
                        onSave(mode)
                        router.modal = nil
                    }
                    .buttonStyle(OrtusPrimaryButtonStyle())
                    .disabled(mode.name.trimmingCharacters(in: .whitespaces).isEmpty || mode.blocked.isEmpty || duplicate != nil)
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
                    targetRow(preset.title) { BrandGlyph(id: preset.id, size: 18) } remove: { selection.set(preset, enabled: false) }
                    OrtusGroupDivider()
                }
                ForEach(otherWebsites, id: \.self) { domain in
                    targetRow(domain) { BrandGlyph(id: BrandGlyph.websiteID(for: domain) ?? "", size: 18) } remove: { selection.websites.removeAll { $0 == domain } }
                    OrtusGroupDivider()
                }
                ForEach(otherApplications) { app in
                    targetRow(app.name) { appIcon(app) } remove: { selection.applications.removeAll { $0.id == app.id } }
                    OrtusGroupDivider()
                }
                HStack(spacing: 14) {
                    OrtusIcon(.plus, size: 16).frame(width: 22)
                    TextField("", text: $website, prompt: Text("Add a website").foregroundStyle(OrtusTheme.textMuted))
                        .textFieldStyle(.plain).font(OrtusTheme.Typo.bodyMedium)
                        .onSubmit(addWebsite)
                        .accessibilityLabel("Website to block")
                    if !website.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add", action: addWebsite).buttonStyle(OrtusRowButtonStyle())
                    }
                }
                .padding(.horizontal, OrtusTheme.spacingMD).padding(.vertical, 12)
                OrtusGroupDivider()
                Button(action: chooseApplications) {
                    HStack(spacing: 14) {
                        OrtusIcon(.plus, size: 16).frame(width: 22)
                        Text("Add an app from Applications…").font(OrtusTheme.Typo.headline).underline()
                        Spacer()
                    }
                    .padding(.horizontal, OrtusTheme.spacingMD).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(OrtusPressableStyle(cornerRadius: 0))
            }
            .overlay(RoundedRectangle(cornerRadius: OrtusTheme.radiusLG, style: .continuous).strokeBorder(OrtusTheme.line, lineWidth: 1))

            if let inputError {
                HStack(alignment: .top, spacing: 8) {
                    OrtusProblemIcon(size: 16)
                    Text(inputError).font(OrtusTheme.Typo.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if !selection.applications.isEmpty {
                Text("Apps in this mode close when focus starts.").font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
            }

            if !suggestedPresets.isEmpty {
                VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                    OrtusSectionHeader(title: "Suggestions")
                    FlowLayout(spacing: 8) {
                        ForEach(suggestedPresets) { preset in
                            Button { selection.set(preset, enabled: true) } label: {
                                HStack(spacing: 7) {
                                    BrandGlyph(id: preset.id, size: 14)
                                    Text(preset.title).font(OrtusFont.text(13, .semibold))
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(OrtusTheme.fill))
                                .foregroundStyle(OrtusTheme.text)
                            }
                            .buttonStyle(OrtusPressableStyle(cornerRadius: 10))
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
                OrtusIcon(.close, size: 10).foregroundStyle(OrtusTheme.text)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(OrtusTheme.fill))
                    .contentShape(Rectangle())
            }
            .buttonStyle(OrtusPressableStyle(cornerRadius: 8)).accessibilityLabel("Remove \(title)")
        }
    }

    private func appIcon(_ app: BlockedApplication) -> some View {
        Group {
            if let id = BrandGlyph.applicationID(for: app) {
                BrandGlyph(id: id, size: 18)
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
            } else {
                OrtusIcon(.app, size: 18)
            }
        }
        .frame(width: 18, height: 18)
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
            if connected { OrtusIcon(.shield, size: 18) } else { OrtusProblemIcon(size: 18) }
        } trailing: {
            Button(connected ? "Add browser" : "Set up") { router.modal = .browserSetup }
                .buttonStyle(OrtusRowButtonStyle())
        }
    }
}

/// During focus, one browser problem at a time: the countdown to closing a browser whose
/// extension is off replaces "not set up", which says the same thing less precisely.
struct ClosingBrowserRow: View {
    @ObservedObject var service: WebsiteBlockingService
    let showSetupProblem: Bool
    @EnvironmentObject var router: PanelRouter
    @Environment(\.snapshotState) private var snapshotState

    private var snapshotClosing: WebsiteBlockingService.ClosingBrowser? {
        switch snapshotState {
        case "closing-browser": .init(name: "Arc", closesAt: .now + 42)
        case "closing-browser-incognito": .init(name: "Google Chrome", closesAt: .now + 42, bundleID: "com.google.Chrome", incognitoOff: true)
        default: nil
        }
    }

    var body: some View {
        if let closing = service.closingBrowser ?? snapshotClosing {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                OrtusProblemCard(title: "\(closing.name) closes in \(FocusView.formatDuration(max(0, closing.closesAt.timeIntervalSince(context.date))))",
                                 detail: closing.incognitoOff ? "The Ortus extension isn’t allowed in incognito."
                                     : "The Ortus extension is off, removed or not allowed in incognito.",
                                 action: closing.incognitoOff ? "Allow" : "Fix") {
                    if closing.incognitoOff { service.openIncognitoSetting(browserID: closing.bundleID) } else { router.modal = .browserSetup }
                }
            }
        } else if showSetupProblem {
            OrtusProblemCard(title: "Website blocking isn’t set up", detail: "Sites stay open this session.", action: "Set up") {
                router.modal = .browserSetup
            }
        }
    }
}

/// The setup steps, shown in a modal. The Chrome Web Store is the install path.
/// Ortus Preview also shows "Install from a folder" (Load unpacked), the only way it connects.
struct BrowserSetupModal: View {
    @ObservedObject var service: WebsiteBlockingService
    @EnvironmentObject var router: PanelRouter
    @Environment(\.snapshotState) private var snapshotState
    @State private var showFolderInstall = false

    /// Detail under step 1, for the browsers it offers.
    private func storeDetail(_ suggested: [SupportedBrowser]) -> String? {
        if service.availableBrowsers.isEmpty { return "Safari and Firefox aren't supported." }
        if suggested.isEmpty { return "Added in " + ListFormatter.localizedString(byJoining: service.connectedBrowsers) + "." }
        if suggested.count > 1 { return "Opens the Chrome Web Store in that browser." }
        return nil
    }

    var body: some View {
        // Only the browsers this person uses and hasn't connected yet, their default first.
        let suggested = service.suggestedBrowsers
        OrtusModal(title: "Block websites in your browser", onClose: { router.modal = nil }) {
            VStack(alignment: .leading, spacing: OrtusTheme.spacingMD) {
                Text("A one-time setup in each browser you use, from the Chrome Web Store.")
                    .font(OrtusTheme.Typo.callout).foregroundStyle(OrtusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                OrtusGroup {
                    VStack(alignment: .leading, spacing: 0) {
                        OrtusStepRow(number: 1, title: "Add the Ortus extension", detail: storeDetail(suggested)) {
                            if suggested.count == 1, let browser = suggested.first {
                                Button("Add to \(browser.name)") { service.openStoreListing(browserID: browser.id) }
                                    .buttonStyle(OrtusSecondaryButtonStyle(size: .small))
                            } else if service.availableBrowsers.isEmpty {
                                Button("Open store") { service.openStoreListing(browserID: nil) }
                                    .buttonStyle(OrtusSecondaryButtonStyle(size: .small))
                            }
                        }
                        if suggested.count > 1 {
                            FlowLayout {
                                ForEach(suggested) { browser in
                                    Button("Add to \(browser.name)") { service.openStoreListing(browserID: browser.id) }
                                        .buttonStyle(OrtusSecondaryButtonStyle(size: .small))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 52)
                            .padding(.trailing, OrtusTheme.spacingMD)
                            .padding(.bottom, 12)
                        }
                    }
                    OrtusGroupDivider()
                    // Without it, blocked sites stay open in private windows, and Ortus closes the browser during focus.
                    OrtusStepRow(number: 2, title: "Turn on Allow in Incognito", detail: "In the extension’s Details, so private windows are covered.") { EmptyView() }
                }
                // Load unpacked is only for the preview: it connects to its own folder, not the store build.
                if service.preview {
                    VStack(alignment: .leading, spacing: OrtusTheme.spacingSM) {
                        Button { withAnimation(.easeOut(duration: 0.18)) { showFolderInstall.toggle() } } label: {
                            HStack(spacing: 8) {
                                    OrtusIcon(.chevronRight, size: 14)
                                    .rotationEffect(.degrees(showFolderInstall ? 90 : 0))
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Install from a folder").font(OrtusFont.text(14, .bold))
                                    Text("This preview connects only to the extension in this folder. The store extension connects to Ortus.")
                                        .font(OrtusTheme.Typo.caption).foregroundStyle(OrtusTheme.textMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(OrtusPressableStyle(inset: 4))
                        .accessibilityLabel("Install from a folder")
                        .accessibilityValue(showFolderInstall ? "Expanded" : "Collapsed")
                        if showFolderInstall {
                            OrtusGroup {
                                VStack(alignment: .leading, spacing: 0) {
                                    OrtusStepRow(number: 1, title: "Open the extensions page") {
                                        if service.availableBrowsers.count == 1, let browser = service.availableBrowsers.first {
                                            Button(browser.name) { service.openExtensionsPage(browserID: browser.id) }
                                                .buttonStyle(OrtusSecondaryButtonStyle(size: .small))
                                        }
                                    }
                                    if service.availableBrowsers.count > 1 {
                                        FlowLayout {
                                            ForEach(service.availableBrowsers) { browser in
                                                Button(browser.name) { service.openExtensionsPage(browserID: browser.id) }
                                                    .buttonStyle(OrtusSecondaryButtonStyle(size: .small))
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 52)
                                        .padding(.trailing, OrtusTheme.spacingMD)
                                        .padding(.bottom, 12)
                                    }
                                }
                                OrtusGroupDivider()
                                OrtusStepRow(number: 2, title: "Turn on Developer mode, then click Load unpacked") { EmptyView() }
                                OrtusGroupDivider()
                                OrtusStepRow(number: 3, title: "Choose the “\(service.extensionDirectory?.lastPathComponent ?? "Ortus Browser")” folder") {
                                    Button("Show folder") { service.revealCompanion() }.buttonStyle(OrtusSecondaryButtonStyle(size: .small))
                                }
                            }
                        }
                    }
                }
                if let error = service.setupError ?? service.error ?? service.enforcementError {
                    HStack(alignment: .top, spacing: 8) {
                        OrtusProblemIcon(size: 16)
                        Text(error).font(OrtusTheme.Typo.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    if !service.connectedBrowsers.isEmpty {
                        HStack(spacing: 6) {
                            OrtusIcon(.check, size: 14)
                            Text("Connected to \(service.connectedBrowsers.joined(separator: ", "))")
                        }
                        .font(OrtusFont.text(13, .semibold))
                    }
                    Spacer()
                    Button("Done") { router.modal = nil }.buttonStyle(OrtusPrimaryButtonStyle())
                }
            }
        }
        .onAppear { if snapshotState?.hasPrefix("browser-setup-folder") == true { showFolderInstall = true } }
    }
}
