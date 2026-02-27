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
            // Tab bar
            HStack(spacing: 2) {
                ForEach(tabs, id: \.2) { title, icon, tag in
                    Button {
                        selectedTab = tag
                    } label: {
                        Label(title, systemImage: icon)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tag ? OrtusTheme.accentSoft : Color.clear)
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTab == tag ? .primary : .tertiary)
                }

                // Settings — compact gear icon
                Button {
                    selectedTab = 3
                } label: {
                    Image(systemName: selectedTab == 3 ? "gearshape.fill" : "gearshape")
                        .font(.subheadline)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(selectedTab == 3 ? OrtusTheme.accentSoft : Color.clear)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == 3 ? .primary : .tertiary)
            }
            .padding(.horizontal, OrtusTheme.spacingSM)
            .padding(.top, OrtusTheme.spacingSM)
            .animation(.easeInOut(duration: 0.2), value: selectedTab)

            Divider()
                .padding(.top, OrtusTheme.spacingXS)

            // Content
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
        }
        .frame(width: 400, height: 520)
        .background(VibrantBackground())
    }
}
