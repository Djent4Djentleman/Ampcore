import SwiftUI
import CoreData

// MARK: - Artists

struct ArtistsView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDTrack.artist, ascending: true)],
        animation: .default
    )
    private var tracks: FetchedResults<CDTrack>

    private var artists: [(display: String, key: String)] {
        let values: [String] = tracks.compactMap { t in
            let s = (t.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? "Unknown Artist" : s
        }
        let unique = Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return unique.map { name in
            // key must match what we store in CoreData (empty string for unknown)
            let key = (name == "Unknown Artist") ? "" : name
            return (name, key)
        }
    }

    var body: some View {
        List {
            if artists.isEmpty {
                ContentUnavailableView("No Artists", systemImage: "person.2.fill")
            } else {
                ForEach(artists, id: \.key) { a in
                    NavigationLink(a.display) {
                        ArtistDetailView(artistKey: a.key, artistDisplay: a.display)
                    }
                }
            }
        }
        .navigationTitle("Artists")
    }
}

private struct ArtistDetailView: View {
    let artistKey: String
    let artistDisplay: String

    @FetchRequest private var tracks: FetchedResults<CDTrack>

    init(artistKey: String, artistDisplay: String) {
        self.artistKey = artistKey
        self.artistDisplay = artistDisplay
        _tracks = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \CDTrack.album, ascending: true),
                NSSortDescriptor(keyPath: \CDTrack.title, ascending: true)
            ],
            predicate: NSPredicate(format: "artist == %@", artistKey),
            animation: .default
        )
    }

    var body: some View {
        List {
            if tracks.isEmpty {
                ContentUnavailableView("No Songs", systemImage: "music.note")
            } else {
                ForEach(tracks, id: \.objectID) { t in
                    TrackRowView(track: t)
                }
            }
        }
        .navigationTitle(artistDisplay)
    }
}

// MARK: - Albums

struct AlbumsView: View {
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \CDTrack.album, ascending: true),
            NSSortDescriptor(keyPath: \CDTrack.artist, ascending: true)
        ],
        animation: .default
    )
    private var tracks: FetchedResults<CDTrack>

    private struct AlbumItem: Hashable {
        let albumDisplay: String
        let albumKey: String
        let artistDisplay: String
        let artistKey: String
    }

    private var albums: [AlbumItem] {
        var set = Set<AlbumItem>()
        for t in tracks {
            let album = (t.album ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = (t.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let albumDisplay = album.isEmpty ? "Unknown Album" : album
            let artistDisplay = artist.isEmpty ? "Unknown Artist" : artist
            set.insert(AlbumItem(
                albumDisplay: albumDisplay,
                albumKey: albumDisplay == "Unknown Album" ? "" : albumDisplay,
                artistDisplay: artistDisplay,
                artistKey: artistDisplay == "Unknown Artist" ? "" : artistDisplay
            ))
        }
        return Array(set).sorted {
            let a = $0.albumDisplay.localizedCaseInsensitiveCompare($1.albumDisplay)
            if a != .orderedSame { return a == .orderedAscending }
            return $0.artistDisplay.localizedCaseInsensitiveCompare($1.artistDisplay) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if albums.isEmpty {
                ContentUnavailableView("No Albums", systemImage: "square.stack.fill")
            } else {
                ForEach(albums, id: \.self) { a in
                    NavigationLink {
                        AlbumDetailView(albumKey: a.albumKey, artistKey: a.artistKey, title: a.albumDisplay)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(a.albumDisplay)
                            Text(a.artistDisplay)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Albums")
    }
}

private struct AlbumDetailView: View {
    let albumKey: String
    let artistKey: String
    let title: String

    @FetchRequest private var tracks: FetchedResults<CDTrack>

    init(albumKey: String, artistKey: String, title: String) {
        self.albumKey = albumKey
        self.artistKey = artistKey
        self.title = title
        _tracks = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDTrack.title, ascending: true)],
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "album == %@", albumKey),
                NSPredicate(format: "artist == %@", artistKey)
            ]),
            animation: .default
        )
    }

    var body: some View {
        List {
            if tracks.isEmpty {
                ContentUnavailableView("No Songs", systemImage: "music.note")
            } else {
                ForEach(tracks, id: \.objectID) { t in
                    TrackRowView(track: t)
                }
            }
        }
        .navigationTitle(title)
    }
}

// MARK: - Genres

struct GenresView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDTrack.genre, ascending: true)],
        animation: .default
    )
    private var tracks: FetchedResults<CDTrack>

    private var genres: [(display: String, key: String)] {
        let values: [String] = tracks.compactMap { t in
            let s = (t.genre ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? "Unknown Genre" : s
        }
        let unique = Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return unique.map { g in
            let key = (g == "Unknown Genre") ? "" : g
            return (g, key)
        }
    }

    var body: some View {
        List {
            if genres.isEmpty {
                ContentUnavailableView("No Genres", systemImage: "tag.fill")
            } else {
                ForEach(genres, id: \.key) { g in
                    NavigationLink(g.display) {
                        GenreDetailView(genreKey: g.key, title: g.display)
                    }
                }
            }
        }
        .navigationTitle("Genres")
    }
}

private struct GenreDetailView: View {
    let genreKey: String
    let title: String

    @FetchRequest private var tracks: FetchedResults<CDTrack>

    init(genreKey: String, title: String) {
        self.genreKey = genreKey
        self.title = title
        _tracks = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \CDTrack.artist, ascending: true),
                NSSortDescriptor(keyPath: \CDTrack.album, ascending: true),
                NSSortDescriptor(keyPath: \CDTrack.title, ascending: true)
            ],
            predicate: NSPredicate(format: "genre == %@", genreKey),
            animation: .default
        )
    }

    var body: some View {
        List {
            if tracks.isEmpty {
                ContentUnavailableView("No Songs", systemImage: "music.note")
            } else {
                ForEach(tracks, id: \.objectID) { t in
                    TrackRowView(track: t)
                }
            }
        }
        .navigationTitle(title)
    }
}

// MARK: - Years

struct YearsView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDTrack.year, ascending: false)],
        animation: .default
    )
    private var tracks: FetchedResults<CDTrack>

    private var years: [Int] {
        let values = tracks.compactMap { t -> Int? in
            let y = Int(t.year)
            return y > 0 ? y : nil
        }
        return Array(Set(values)).sorted(by: >)
    }

    var body: some View {
        List {
            if years.isEmpty {
                ContentUnavailableView("No Years", systemImage: "calendar")
            } else {
                ForEach(years, id: \.self) { y in
                    NavigationLink(String(y)) {
                        YearDetailView(year: y)
                    }
                }
            }
        }
        .navigationTitle("Years")
    }
}

private struct YearDetailView: View {
    let year: Int
    @FetchRequest private var tracks: FetchedResults<CDTrack>

    init(year: Int) {
        self.year = year
        _tracks = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \CDTrack.artist, ascending: true),
                NSSortDescriptor(keyPath: \CDTrack.album, ascending: true),
                NSSortDescriptor(keyPath: \CDTrack.title, ascending: true)
            ],
            predicate: NSPredicate(format: "year == %d", year),
            animation: .default
        )
    }

    var body: some View {
        List {
            if tracks.isEmpty {
                ContentUnavailableView("No Songs", systemImage: "music.note")
            } else {
                ForEach(tracks, id: \.objectID) { t in
                    TrackRowView(track: t)
                }
            }
        }
        .navigationTitle(String(year))
    }
}

// MARK: - Favorites

struct FavoritesView: View {
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \CDTrack.artist, ascending: true),
            NSSortDescriptor(keyPath: \CDTrack.album, ascending: true),
            NSSortDescriptor(keyPath: \CDTrack.title, ascending: true)
        ],
        predicate: NSPredicate(format: "isFavorite == YES"),
        animation: .default
    )
    private var tracks: FetchedResults<CDTrack>

    var body: some View {
        List {
            if tracks.isEmpty {
                ContentUnavailableView("No Favorites", systemImage: "heart.fill")
            } else {
                ForEach(tracks, id: \.objectID) { t in
                    TrackRowView(track: t)
                }
            }
        }
        .navigationTitle("Favorites")
    }
}

// MARK: - Recently Added

struct RecentlyAddedView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDTrack.addedAt, ascending: false)],
        animation: .default
    )
    private var tracks: FetchedResults<CDTrack>

    var body: some View {
        List {
            if tracks.isEmpty {
                ContentUnavailableView("No Recent Tracks", systemImage: "clock")
            } else {
                ForEach(tracks, id: \.objectID) { t in
                    TrackRowView(track: t)
                }
            }
        }
        .navigationTitle("Recently Added")
    }
}

// MARK: - Long Tracks (>= 15 minutes)

struct LongTracksView: View {
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \CDTrack.duration, ascending: false),
            NSSortDescriptor(keyPath: \CDTrack.title, ascending: true)
        ],
        predicate: NSPredicate(format: "duration >= %f", 15.0 * 60.0),
        animation: .default
    )
    private var tracks: FetchedResults<CDTrack>

    var body: some View {
        List {
            if tracks.isEmpty {
                ContentUnavailableView("No Long Tracks", systemImage: "timer")
            } else {
                ForEach(tracks, id: \.objectID) { t in
                    TrackRowView(track: t)
                }
            }
        }
        .navigationTitle("Long")
    }
}

// MARK: - Playlists (basic list)

struct PlaylistsView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDPlaylist.createdAt, ascending: false)],
        animation: .default
    )
    private var playlists: FetchedResults<CDPlaylist>

    var body: some View {
        List {
            if playlists.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list")
            } else {
                ForEach(playlists, id: \.objectID) { p in
                    NavigationLink(p.name) {
                        PlaylistDetailView(playlistName: p.name)
                    }
                }
            }
        }
        .navigationTitle("Playlists")
    }
}

private struct PlaylistDetailView: View {
    let playlistName: String

    var body: some View {
        ContentUnavailableView(
            "Playlist",
            systemImage: "music.note.list",
            description: Text(playlistName)
        )
        .navigationTitle(playlistName)
    }
}
