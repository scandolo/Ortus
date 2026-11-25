import SwiftUI

struct ContentView: View {
    @EnvironmentObject var claudeCodeService: ClaudeCodeService
    @EnvironmentObject var updateService: UpdateService
    @EnvironmentObject var focusManager: FocusManager
    @EnvironmentObject var router: PanelRouter
    @State private var selectedTab: Int
    private let fixedHeight: CGFloat?

    /// `initialTab` and `fixedHeight` exist for the debug snapshot harness.
    init(initialTab: Int = 0, fixedHeight: CGFloat? = nil) {
        _selectedTab = State(initialValue: initialTab)
        self.fixedHeight = fixedHeight
    }

    /// Size the host itself. Scaling a sized MenuBarExtra can leave drawing and
    /// clipping bounds out of sync during presentation.
    private static let designSize = CGSize(width: 420, height: 560)

    private let tabs: [(String, OrtusIcon.Name, Int)] = [
        ("Focus", .focus, 0),
        ("Schedule", .schedule, 1),
        ("Agent", .agent, 2),
    ]

    var body: some View {
        let size = fixedHeight.map { CGSize(width: Self.designSize.width, height: $0) } ?? Self.panelSize()
        VStack(spacing: 0) {
            tabBar

            Group {
                switch selectedTab {
                case 0: FocusView()
                case 1: ScheduleView()
                case 2: ChatView()
                case 3: SettingsView()
                default: FocusView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .frame(width: size.width, height: size.height)
        .foregroundStyle(OrtusTheme.text)
        .font(OrtusTheme.Typo.body)
        .background(VibrantBackground())
        .overlay { modal }
        // Bone while free, ink while locked, whatever macOS is set to.
        .ortusLockAppearance(locked: focusManager.isInFocus)
        .onAppear {
            claudeCodeService.detectIfNeeded()
            Task { await updateService.checkForUpdates() }
        }
        .onReceive(router.$requestedTab.compactMap { $0 }) { tab in
            selectedTab = tab
            router.requestedTab = nil
        }
    }

    @ViewBuilder private var modal: some View {
        switch router.modal {
        case .browserSetup: BrowserSetupModal(service: focusManager.websites)
        case .slackSetup: SlackSetupModal()
        case .chatSetup: ChatSetupModal()
        case .chatIntro: ChatIntroModal()
        case let .focusIntro(selection, minutes, onConfirm):
            FocusIntroModal(selection: selection, minutes: minutes, onConfirm: onConfirm)
        case let .modeEditor(mode, onSave): ModeEditor(mode: mode, onSave: onSave)
        case .endFocusEarly:
            OrtusAlert(title: "End focus early?",
                       message: "Everything unlocks now. You have 1 early end left this week.",
                       cancel: "Keep going", confirm: "End now", onCancel: { router.modal = nil }) {
                router.modal = nil
                focusManager.emergencyEndFocusSession()
            }
        case nil: EmptyView()
        }
    }

    /// Constrain the viewport on smaller screens; the content scrolls at its
    /// normal text size instead of transforming the entire hosted window.
    private static func panelSize() -> CGSize {
        guard let visible = NSScreen.main?.visibleFrame else { return designSize }
        return CGSize(
            width: min(designSize.width, max(280, visible.width - 24)),
            height: min(designSize.height, max(320, visible.height * 0.72))
        )
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.2) { title, icon, tag in
                TabButton(
                    title: title,
                    icon: icon,
                    isSelected: selectedTab == tag
                ) {
                    withAnimation(.easeOut(duration: 0.18)) { selectedTab = tag }
                }
            }

            SettingsTabButton(isSelected: selectedTab == 3) {
                withAnimation(.easeOut(duration: 0.18)) { selectedTab = 3 }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(OrtusTheme.fill))
        .padding(.horizontal, OrtusTheme.spacingMD)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let title: String
    let icon: OrtusIcon.Name
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                OrtusIcon(icon, size: 16)
                Text(title).font(OrtusFont.text(13, isSelected ? .bold : .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? OrtusTheme.strong : (isHovering ? OrtusTheme.text.opacity(0.06) : .clear))
            )
            .contentShape(Rectangle())
            .foregroundStyle(isSelected ? OrtusTheme.onStrong : OrtusTheme.textMuted)
        }
        .buttonStyle(OrtusPressableStyle(highlight: false))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
    }
}

// MARK: - Settings

private struct SettingsTabButton: View {
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            OrtusIcon(.settings, size: 16)
                .frame(width: 44, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? OrtusTheme.strong : (isHovering ? OrtusTheme.text.opacity(0.06) : .clear))
                )
                .contentShape(Rectangle())
                .foregroundStyle(isSelected ? OrtusTheme.onStrong : OrtusTheme.textMuted)
        }
        .buttonStyle(OrtusPressableStyle(highlight: false))
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
    }
}
