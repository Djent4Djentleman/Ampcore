import Foundation
import Combine

@MainActor
final class AppNavigation: ObservableObject {
    enum Screen: Equatable {
        case library
        case player
    }

    enum Sheet: Equatable, Identifiable {
        case queue
        case lyrics
        case settings
        case eq
        case search

        var id: String {
            switch self {
            case .queue: return "queue"
            case .lyrics: return "lyrics"
            case .settings: return "settings"
            case .eq: return "eq"
            case .search: return "search"
            }
        }
    }

    @Published var screen: Screen = .library
    @Published var sheet: Sheet?

    func showLibrary() { screen = .library } // Go library
    func showPlayer() { screen = .player } // Go player

    func showQueue() { sheet = .queue } // Show queue
    func showLyrics() { sheet = .lyrics } // Show lyrics
    func showSettings() { sheet = .settings } // Show settings
    func showEQ() { sheet = .eq } // Show EQ
    func showSearch() { sheet = .search } // Show search

    func dismissSheet() { sheet = nil } // Close sheet
}
