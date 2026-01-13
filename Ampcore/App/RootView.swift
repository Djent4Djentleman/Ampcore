import SwiftUI

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    
    private enum RootTab: Hashable {
        case library
        case player
        case search
        case settings
    }
    
    @State private var tab: RootTab = .library
    
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                LibraryHomeView()
            }
            .tabItem { Label("Library", systemImage: "music.note.list") }
            .tag(RootTab.library)
            
            NavigationStack {
                PlayerView()
            }
            .tabItem { Label("Player", systemImage: "play.circle") }
            .tag(RootTab.player)
            
            NavigationStack {
                SearchView()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(RootTab.search)
            
            NavigationStack {
                SettingsRootView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(RootTab.settings)
        }
        .onAppear {
            tab = (env.navigation.screen == .player) ? .player : .library
        }
        .onChange(of: env.navigation.screen) { _, newValue in
            // Keep external navigation in sync for the two "main" screens
            switch newValue {
            case .library:
                tab = .library
            case .player:
                tab = .player
            }
        }
        .onChange(of: tab) { _, newValue in
            // Update AppNavigation only for the two main screens; other tabs are self-contained.
            switch newValue {
            case .library:
                if env.navigation.screen != .library { env.navigation.screen = .library }
            case .player:
                if env.navigation.screen != .player { env.navigation.screen = .player }
            case .search, .settings:
                break
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
