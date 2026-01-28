import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    
    // Keep the system tab bar blur stable across all tabs (prevents the "jump" when content behind changes).
    private func applyTabBarAppearance() {
        let isDark: Bool
        switch env.settings.theme {
        case .dark: isDark = true
        case .light: isDark = false
        case .system:
            isDark = (UITraitCollection.current.userInterfaceStyle == .dark)
        }
        
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        
        let blurStyle: UIBlurEffect.Style = isDark ? .systemChromeMaterialDark : .systemChromeMaterialLight
        appearance.backgroundEffect = UIBlurEffect(style: blurStyle)
        appearance.backgroundColor = UIColor.black.withAlphaComponent(isDark ? 0.18 : 0.06)
        appearance.shadowColor = UIColor.black.withAlphaComponent(isDark ? 0.25 : 0.12)
        
        let tabBar = UITabBar.appearance()
        tabBar.isTranslucent = true
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }
    
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
            .tabItem {
                Image(systemName: "music.note.list")
                    .font(.system(size: 24, weight: .semibold))
            }
            .tag(RootTab.library)
            
            NavigationStack {
                PlayerView()
            }
            .tabItem {
                Image(systemName: "play.circle")
                    .font(.system(size: 26, weight: .semibold))
            }
            .tag(RootTab.player)
            
            NavigationStack {
                SearchView()
            }
            .tabItem {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .semibold))
            }
            .tag(RootTab.search)
            
            NavigationStack {
                SettingsRootView()
            }
            .tabItem {
                Image(systemName: "gearshape")
                    .font(.system(size: 24, weight: .semibold))
            }
            .tag(RootTab.settings)
        }
        .onAppear {
            applyTabBarAppearance()
            tab = (env.navigation.screen == .player) ? .player : .library
        }
        .onChange(of: env.navigation.screen) { _, newValue in
            switch newValue {
            case .library: tab = .library
            case .player: tab = .player
            }
        }
        .onChange(of: tab) { _, newValue in
            switch newValue {
            case .library:
                if env.navigation.screen != .library { env.navigation.screen = .library }
            case .player:
                if env.navigation.screen != .player { env.navigation.screen = .player }
            case .search, .settings:
                break
            }
        }
        .onChange(of: env.settings.theme) { _, _ in
            applyTabBarAppearance()
        }
        .preferredColorScheme(env.settings.colorScheme)
        .font(Typography.font(env.settings.fontChoice, size: 17, bold: env.settings.boldText))
        .sheet(item: $env.navigation.sheet) { sheet in
            switch sheet {
            case .queue: QueueView()
            case .lyrics: LyricsEditorView()
            case .settings: SettingsRootView()
            case .eq: EQView()
            case .search: SearchView()
            }
        }
    }
}
