import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    private let tabs: [(String, String, Int)] = [
        ("Focus", "sunrise.fill", 0),
        ("Schedule", "calendar", 1),
        ("Chat", "bubble.left.fill", 2),
    ]

    var body: some View {
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
        .frame(width: 420, height: 560)
        .background(VibrantBackground())
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
        .padding(.top, OrtusTheme.spacingMD)
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
