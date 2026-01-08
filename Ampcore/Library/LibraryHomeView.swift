import SwiftUI

struct LibraryHomeView: View {
    enum SectionItem: String, CaseIterable, Identifiable {
        case allSongs = "All Songs"
        case artists = "Artists"
        case albums = "Albums"
        case playlists = "Playlists"
        case queue = "Queue"
        case topRated = "Top rated"
        case lowRated = "Low rated"
        case mostPlayed = "Most played"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .allSongs: return "music.note"
            case .artists: return "person.2.fill"
            case .albums: return "square.stack.fill"
            case .playlists: return "music.note.list"
            case .queue: return "text.line.first.and.arrowtriangle.forward"
            case .topRated: return "star.fill"
            case .lowRated: return "star.slash"
            case .mostPlayed: return "flame.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(SectionItem.allCases) { item in
                    NavigationLink {
                        destinationView(for: item)
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
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
            LibraryView() // твой текущий экран со списком треков
        default:
            PlaceholderSectionView(title: item.rawValue)
        }
    }
}

private struct PlaceholderSectionView: View {
    let title: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text("Coming next.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
