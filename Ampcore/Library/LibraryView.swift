import SwiftUI
import CoreData
import UIKit

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
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(currentRowBackground(for: t))
                        .contentShape(Rectangle())
                        .onTapGesture { tapTrack(t) }
                }
            }
        }
        .navigationTitle("All Songs")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .toolbar {
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
        let view = TrackRowView(
            track: t,
            rowScale: rowScale,
            isCurrent: t.objectID == env.player.currentTrackID,
            isPlaying: env.player.isPlaying
        )
        
        // iOS 17+: subtle "Apple Music"-style shrink while scrolling.
        if #available(iOS 17.0, *) {
            return view.scrollTransition(.animated, axis: .vertical) { content, phase in
                content
                    .scaleEffect(phase.isIdentity ? 1.0 : 0.95)
                    .opacity(phase.isIdentity ? 1.0 : 0.88)
            }
        } else {
            return view
        }
    }
    
    private func currentRowBackground(for t: CDTrack) -> some View {
        Group {
            if t.objectID == env.player.currentTrackID {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            } else {
                Color.clear
            }
        }
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
