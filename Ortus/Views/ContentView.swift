import SwiftUI

struct ContentView: View {
    @EnvironmentObject var focusManager: FocusManager
    @State private var selectedTab = 0
    @Namespace private var navNamespace

    private let tabs: [NavItem] = [
        NavItem(title: "Focus",    icon: "sunrise",        selectedIcon: "sunrise.fill",        tag: 0),
        NavItem(title: "Schedule", icon: "calendar",       selectedIcon: "calendar",            tag: 1),
        NavItem(title: "Chat",     icon: "bubble.left",    selectedIcon: "bubble.left.fill",    tag: 2),
    ]

    var body: some View {
        VStack(spacing: 0) {
            navBar

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
            .id(selectedTab)
            .animation(OrtusTheme.Motion.enter, value: selectedTab)
        }
        .frame(width: 420, height: 560)
        .background(VibrantBackground())
    }

    // MARK: - Floating segmented nav

    private var navBar: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { item in
                NavSegment(
                    item: item,
                    isSelected: selectedTab == item.tag,
                    namespace: navNamespace
                ) {
                    select(item.tag)
                }
            }

            // hairline spacer between primary tabs and the settings gear
            Rectangle()
                .fill(OrtusTheme.hairline)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 2)

            NavGear(isSelected: selectedTab == 3, namespace: navNamespace) {
                select(3)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(OrtusTheme.cardRaised)
                .overlay(Capsule().strokeBorder(OrtusTheme.hairline, lineWidth: 1))
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(colors: [OrtusTheme.innerHighlight, .clear],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                )
        )
        .clipShape(Capsule())
        .modifier(NavShadow())
        .padding(.horizontal, OrtusTheme.spacingMD)
        .padding(.top, OrtusTheme.spacingLG)
        .padding(.bottom, OrtusTheme.spacingSM)
    }

    private func select(_ tag: Int) {
        withAnimation(OrtusTheme.Motion.springy) { selectedTab = tag }
    }
}

private struct NavShadow: ViewModifier {
    func body(content: Content) -> some View { OrtusTheme.Elevation.e2(content) }
}

// MARK: - Nav model

private struct NavItem: Identifiable {
    let title: String
    let icon: String
    let selectedIcon: String
    let tag: Int
    var id: Int { tag }
}

// MARK: - Primary segment

private struct NavSegment: View {
    let item: NavItem
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? item.selectedIcon : item.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(item.title)
                    .font(OrtusTheme.Typo.bodyMedium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(selectionBackground)
            .contentShape(Capsule())
            .foregroundStyle(isSelected ? OrtusTheme.accent : (isHovering ? .primary : .secondary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
    }

    @ViewBuilder private var selectionBackground: some View {
        if isSelected {
            Capsule()
                .fill(OrtusTheme.accentSoft)
                .overlay(Capsule().strokeBorder(OrtusTheme.accent.opacity(0.30), lineWidth: 1))
                .matchedGeometryEffect(id: "navSelection", in: namespace)
        } else if isHovering {
            Capsule().fill(Color.primary.opacity(0.05))
        }
    }
}

// MARK: - Settings gear

private struct NavGear: View {
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isSelected ? "gearshape.fill" : "gearshape")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 38, height: 32)
                .background(background)
                .contentShape(Capsule())
                .foregroundStyle(isSelected ? OrtusTheme.accent : (isHovering ? .primary : .secondary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
    }

    @ViewBuilder private var background: some View {
        if isSelected {
            Capsule()
                .fill(OrtusTheme.accentSoft)
                .overlay(Capsule().strokeBorder(OrtusTheme.accent.opacity(0.30), lineWidth: 1))
                .matchedGeometryEffect(id: "navSelection", in: namespace)
        } else if isHovering {
            Capsule().fill(Color.primary.opacity(0.05))
        }
    }
}
