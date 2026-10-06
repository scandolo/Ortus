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

    private let tabs: [(String, String, Int)] = [
        ("Focus", "sunrise.fill", 0),
        ("Schedule", "calendar", 1),
        ("Chat", "bubble.left.fill", 2),
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
        .background(VibrantBackground())
        .overlay { modal }
        .onAppear {
            claudeCodeService.detectIfNeeded()
            Task { await updateService.checkForUpdates() }
        }
    }

    @ViewBuilder private var modal: some View {
        switch router.modal {
        case .browserSetup: BrowserSetupModal(service: focusManager.websites)
        case .slackSetup: SlackSetupModal()
        case let .modeEditor(mode, onSave): ModeEditor(mode: mode, onSave: onSave)
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

            SettingsGearButton(isSelected: selectedTab == 3) {
                withAnimation(.easeOut(duration: 0.18)) { selectedTab = 3 }
            }
        }
        .padding(4)
        .background(Capsule().fill(OrtusTheme.cardSurface))
        .overlay(Capsule().strokeBorder(OrtusTheme.hairline, lineWidth: 1))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, OrtusTheme.spacingMD)
        .padding(.top, OrtusTheme.spacingLG)
        .padding(.bottom, OrtusTheme.spacingSM)
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(OrtusTheme.Typo.bodyMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? OrtusTheme.accent.opacity(0.18) : (isHovering ? Color.primary.opacity(0.05) : .clear))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? OrtusTheme.accent.opacity(0.30) : .clear, lineWidth: 1)
                )
                .clipShape(Capsule())
                .contentShape(Capsule())
                .foregroundStyle(isSelected ? OrtusTheme.accentInk : OrtusTheme.textMuted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Settings Gear

private struct SettingsGearButton: View {
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isSelected ? "gearshape.fill" : "gearshape")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 38, height: 32)
                .background(
                    Capsule()
                        .fill(isSelected ? OrtusTheme.accent.opacity(0.18) : (isHovering ? Color.primary.opacity(0.05) : .clear))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? OrtusTheme.accent.opacity(0.30) : .clear, lineWidth: 1)
                )
                .clipShape(Capsule())
                .contentShape(Capsule())
                .foregroundStyle(isSelected ? OrtusTheme.accentInk : OrtusTheme.textMuted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .onHover { isHovering = $0 }
    }
}
