import Foundation
import AVFoundation
import os

enum MetadataReader {
    
    struct Metadata {
        var title: String?
        var artist: String?
        var album: String?
        var duration: Double?
        var artworkData: Data?
    }
    
    /// Читает метаданные из файла по URL (внутри security-scope вызови FolderAccess.withAccess)
    static func read(from fileURL: URL) -> Metadata {
        let asset = AVURLAsset(url: fileURL)
        var out = Metadata()
        
        // duration
        let dur = asset.duration
        if dur.isNumeric {
            out.duration = CMTimeGetSeconds(dur)
        }
        
        // common metadata
        let common = asset.commonMetadata
        
        out.title = firstString(common, key: .commonKeyTitle)
        out.artist = firstString(common, key: .commonKeyArtist)
        out.album = firstString(common, key: .commonKeyAlbumName)
        
        // artwork (m4a/mp3 иногда отдаёт data, иногда image)
        if let artworkItem = common.first(where: { $0.commonKey == .commonKeyArtwork }) {
            if let data = artworkItem.dataValue {
                out.artworkData = data
            } else if let imageData = artworkItem.value as? Data {
                out.artworkData = imageData
            }
        }
        
        Log.meta.debug("Metadata read: \(fileURL.lastPathComponent, privacy: .public) title=\(out.title ?? "nil", privacy: .public)")
        
        return out
    }
    
    private static func firstString(_ items: [AVMetadataItem], key: AVMetadataKey) -> String? {
        let item = items.first(where: { $0.commonKey == key })
        if let s = item?.stringValue, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s
        }
        return nil
    }
}
