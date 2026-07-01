import SwiftUI

struct ContentView: View {
    @EnvironmentObject var claudeCodeService: ClaudeCodeService
    @EnvironmentObject var updateService: UpdateService
    @State private var selectedTab = 0

    /// The design size the whole UI is laid out at. On small/zoomed displays the
    /// panel is scaled down to fit (see `fitScale`); it's never enlarged.
    private static let designSize = CGSize(width: 420, height: 560)

    private let tabs: [(String, String, Int)] = [
        ("Focus", "sunrise.fill", 0),
        ("Schedule", "calendar", 1),
        ("Chat", "bubble.left.fill", 2),
    ]

    var body: some View {
        let scale = Self.fitScale()
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
        .frame(width: Self.designSize.width, height: Self.designSize.height)
        .background(VibrantBackground())
        // Scale the entire panel uniformly so it fits the current screen. Keeps the
        // exact same layout everywhere — it just shrinks (never grows) on smaller or
        // more-zoomed displays instead of rendering at a fixed point size that can
        // swallow a 13" screen set to "Larger Text".
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: Self.designSize.width * scale, height: Self.designSize.height * scale)
        .onAppear {
            claudeCodeService.detectIfNeeded()
            Task { await updateService.checkForUpdates() }
        }
    }

    /// How much to shrink the panel so it comfortably fits the active screen.
    /// Returns 1 (no change) on any display with room to spare. The height budget
    /// is the binding constraint on short/zoomed screens; width is rarely the limit.
    private static func fitScale() -> CGFloat {
        guard let visible = NSScreen.main?.visibleFrame else { return 1 }
        // Leave headroom so the panel never butts against the menu bar or screen edge,
        // and cap height usage so it never dominates a short screen even when it fits.
        let heightBudget = visible.height * 0.72
        let widthBudget = visible.width - 24
        let scale = min(heightBudget / designSize.height, widthBudget / designSize.width, 1)
        // Don't shrink into illegibility if someone is on a tiny external display.
        return max(scale, 0.7)
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
                .foregroundStyle(isSelected ? OrtusTheme.accent : .secondary)
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
                .foregroundStyle(isSelected ? OrtusTheme.accent : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .onHover { isHovering = $0 }
    }
}
