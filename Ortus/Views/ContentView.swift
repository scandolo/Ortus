import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            FocusView()
                .tabItem {
                    Label("Focus", systemImage: "sunrise.fill")
                }
                .tag(0)

            ScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
                .tag(1)

            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.fill")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .padding(.top, OrtusTheme.spacingSM)
        .tint(OrtusTheme.primary)
        .frame(width: 400, height: 520)
    }
}
