import SwiftUI

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var tab: AppNavigation.Screen = .library

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                LibraryHomeView()
            }
            .tabItem { Label("Library", systemImage: "music.note.list") }
            .tag(AppNavigation.Screen.library)

            NavigationStack {
                PlayerView()
            }
            .tabItem { Label("Player", systemImage: "play.circle") }
            .tag(AppNavigation.Screen.player)
        }
        .onAppear {
            tab = env.navigation.screen
        }
        .onChange(of: env.navigation.screen) { _, newValue in
            tab = newValue
        }
        .onChange(of: tab) { _, newValue in
            if env.navigation.screen != newValue {
                env.navigation.screen = newValue
            }
        }
        .sheet(item: $env.navigation.sheet) { sheet in
            switch sheet {
            case .queue:
                QueueView()

            case .lyrics:
                LyricsEditorView()

            case .settings:
                SettingsRootView()

            case .eq:
                EQView()

            case .search:
                SearchView()
            }
        }
    }
}
