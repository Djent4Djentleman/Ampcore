import Foundation

/// Лёгкая модель для UI (не CoreData-объект), чтобы не тащить NSManagedObject в SwiftUI.
struct TrackViewModel: Identifiable, Hashable {
    let id: UUID
    
    let title: String
    let artist: String?
    let album: String?
    let duration: Double
    
    let fileBookmark: Data
    let relativePath: String
    
    let artworkData: Data?
    let lyrics: String?
    
    init(from cd: CDTrack) {
        self.id = cd.id
        self.title = cd.title
        
        self.artist = cd.artist
        self.album = cd.album
        self.duration = cd.duration
        
        self.fileBookmark = cd.fileBookmark
        self.relativePath = cd.relativePath
        
        self.artworkData = cd.artworkData
        self.lyrics = cd.lyrics
    }
    
    // MARK: - UI Helpers
    
    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Title" : title
    }
    
    var displayArtist: String {
        let a = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return a.isEmpty ? "Unknown Artist" : a
    }
    
    var displayAlbum: String? {
        let al = (album ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return al.isEmpty ? nil : al
    }
    
    /// То, чего не хватает: строка "Artist • Album" (или только Artist)
    var artistAlbumLine: String {
        if let al = displayAlbum {
            return "\(displayArtist) • \(al)"
        }
        return displayArtist
    }
    
    var durationText: String {
        Formatters.time(duration)
    }
}
