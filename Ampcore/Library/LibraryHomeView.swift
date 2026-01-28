import SwiftUI

struct LibraryHomeView: View {
    enum SectionItem: String, CaseIterable, Identifiable {
        case allSongs = "All Songs"
        case artists = "Artists"
        case albums = "Albums"
        case genres = "Genres"
        case years = "Years"
        case favorites = "Favorites"
        case queue = "Queue"
        case playlists = "Playlists"
        case recentlyAdded = "Recently Added"
        case longTracks = "Long"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .allSongs: return "music.note"
            case .artists: return "person.2.fill"
            case .albums: return "square.stack.fill"
            case .genres: return "tag.fill"
            case .years: return "calendar"
            case .favorites: return "heart.fill"
            case .queue: return "text.line.first.and.arrowtriangle.forward"
            case .playlists: return "music.note.list"
            case .recentlyAdded: return "clock"
            case .longTracks: return "timer"
            }
        }

        var isQueue: Bool {
            self == .queue
        }
    }

    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        NavigationStack {
            List {
                ForEach(SectionItem.allCases) { item in
                    if item.isQueue {
                        Button {
                            env.navigation.showQueue()
                        } label: {
                            Label(item.rawValue, systemImage: item.icon)
                        }
                    } else {
                        NavigationLink {
                            destinationView(for: item)
                        } label: {
                            Label(item.rawValue, systemImage: item.icon)
                        }
                    }
                }
            }
            .navigationTitle("Library")
        }
    }

    @ViewBuilder
    private func destinationView(for item: SectionItem) -> some View {
        switch item {
        case .allSongs:
            LibraryView()
        case .artists:
            ArtistsView()
        case .albums:
            AlbumsView()
        case .genres:
            GenresView()
        case .years:
            YearsView()
        case .favorites:
            FavoritesView()
        case .playlists:
            PlaylistsView()
        case .recentlyAdded:
            RecentlyAddedView()
        case .longTracks:
            LongTracksView()
        case .queue:
            EmptyView() // handled by sheet button above
        }
    }
}
