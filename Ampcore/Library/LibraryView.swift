import SwiftUI
import CoreData

struct LibraryView: View {
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var env: AppEnvironment
    
    @State private var rowScale: CGFloat = 1.0
    @State private var sort: LibrarySort = .artist
    @State private var ascending: Bool = true
    @State private var searchText: String = ""
    
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \CDTrack.addedAt, ascending: false)
        ],
        animation: .default
    )
    private var tracks: FetchedResults<CDTrack>
    
    var body: some View {
        List {
            if filteredTracks.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No music in Library" : "No results",
                    systemImage: "music.note.list",
                    description: Text(
                        searchText.isEmpty
                        ? "Pick a folder in Settings, then rescan."
                        : "Try a different search."
                    )
                )
            } else {
                ForEach(filteredTracks, id: \.objectID) { t in
                    row(t)
                        .listRowBackground(currentRowBackground(for: t))
                        .contentShape(Rectangle())
                        .onTapGesture { tapTrack(t) }
                }
            }
        }
        .navigationTitle("All Songs")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    env.navigation.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(LibrarySort.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    
                    Divider()
                    
                    Button {
                        ascending.toggle()
                    } label: {
                        Label(
                            ascending ? "Ascending" : "Descending",
                            systemImage: ascending ? "arrow.up" : "arrow.down"
                        )
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .gesture(pinchGesture)
    }
    
    // MARK: - Search + Sorting
    
    private var filteredTracks: [CDTrack] {
        let base = displayTracks
        
        guard !searchText.isEmpty else { return base }
        
        let q = searchText.lowercased()
        
        return base.filter { t in
            t.title.lowercased().contains(q) ||
            (t.artist?.lowercased().contains(q) ?? false) ||
            (t.album?.lowercased().contains(q) ?? false)
        }
    }
    
    private var displayTracks: [CDTrack] {
        let a = Array(tracks)
        
        func cmp(_ lhs: CDTrack, _ rhs: CDTrack) -> Bool {
            switch sort {
            case .title:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                
            case .artist:
                let la = lhs.artist ?? ""
                let ra = rhs.artist ?? ""
                let r = la.localizedCaseInsensitiveCompare(ra)
                return r == .orderedSame
                ? lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                : r == .orderedAscending
                
            case .album:
                let la = lhs.album ?? ""
                let ra = rhs.album ?? ""
                let r = la.localizedCaseInsensitiveCompare(ra)
                return r == .orderedSame
                ? lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                : r == .orderedAscending
                
            case .added:
                return lhs.addedAt < rhs.addedAt
            }
        }
        
        let sorted = a.sorted { l, r in
            let forward = cmp(l, r)
            return ascending ? forward : !forward
        }
        
        return sorted
    }
    
    // MARK: - Row
    
    private func row(_ t: CDTrack) -> some View {
        HStack(spacing: 12) {
            artwork(t)
                .frame(width: 46 * rowScale, height: 46 * rowScale)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(t.title)
                    .font(.system(size: 15 * rowScale, weight: .semibold))
                    .lineLimit(1)
                
                Text([t.artist, t.album].compactMap { $0 }.joined(separator: " • "))
                    .font(.system(size: 12 * rowScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if t.objectID == env.player.currentTrackID {
                Image(systemName: env.player.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6 * rowScale)
    }
    
    private func artwork(_ t: CDTrack) -> some View {
        Group {
            if let d = t.artworkData, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image("DefaultArtwork").resizable().scaledToFill()
            }
        }
        .clipped()
    }
    
    private func currentRowBackground(for t: CDTrack) -> Color {
        t.objectID == env.player.currentTrackID
        ? Color.secondary.opacity(0.14)
        : Color.clear
    }
    
    // MARK: - Actions
    
    private func tapTrack(_ t: CDTrack) {
        env.playFromLibrary(t, allTracks: filteredTracks)
    }
    
    // MARK: - Gestures
    
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { v in
                rowScale = Swift.min(Swift.max(v, 0.85), 1.4)
            }
    }
    
    // MARK: - Sort enum
    
    private enum LibrarySort: String, CaseIterable, Hashable {
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        case added = "Added"
    }
}
