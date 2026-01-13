import Foundation
import CoreData
import AVFoundation
import UIKit

enum MusicScanner {
    struct ScanResult { let added: Int; let updated: Int }

    // Supported exts
    private static let supportedExts: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac"
    ]

    static func scanAndUpsert(
        folderURL: URL,
        folderBookmark: Data?,
        context: NSManagedObjectContext
    ) throws -> ScanResult {

        guard let folderBookmark else { throw FolderAccessError.bookmarkMissing }

        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isHiddenKey,
            .nameKey
        ]

        let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        )

        var added = 0
        var updated = 0

        try context.performAndWait {
            while let url = enumerator?.nextObject() as? URL {
                let ext = url.pathExtension.lowercased()
                if !supportedExts.contains(ext) { continue }

                if let values = try? url.resourceValues(forKeys: Set(keys)) {
                    if values.isHidden == true { continue }
                    if values.isRegularFile != true { continue }
                }

                let rel = relativePath(of: url, inside: folderURL)

                let req: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
                req.fetchLimit = 1
                req.predicate = NSPredicate(format: "relativePath == %@", rel)

                let existing = try context.fetch(req).first
                let track = existing ?? CDTrack(context: context)

                if existing == nil {
                    track.id = UUID()
                    track.addedAt = Date()
                    added += 1
                } else {
                    updated += 1
                }

                let meta = readMetadataSync(from: url)
                let baseName = url.deletingPathExtension().lastPathComponent

                track.title = (meta.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? baseName
                track.artist = (meta.artist?.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
                track.album = (meta.album?.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""

                if let d = meta.duration, d.isFinite, d > 0 {
                    track.duration = d
                }

                if let art = meta.artworkData {
                    track.artworkData = art
                }

                track.fileBookmark = folderBookmark
                track.relativePath = rel
                track.fileExt = ext
                track.isSupported = true
            }

            if context.hasChanges {
                try context.save()
            }
        }

        return ScanResult(added: added, updated: updated)
    }

    private struct SyncMeta {
        var title: String?
        var artist: String?
        var album: String?
        var duration: Double?
        var artworkData: Data?
    }

    private static func readMetadataSync(from url: URL) -> SyncMeta {
        let asset = AVURLAsset(url: url)
        var out = SyncMeta()

        let dur = CMTimeGetSeconds(asset.duration)
        if dur.isFinite, dur > 0 { out.duration = dur }

        func firstString(_ items: [AVMetadataItem], _ commonKey: AVMetadataKey) -> String? {
            guard let item = items.first(where: { $0.commonKey == commonKey }) else { return nil }
            if let s = item.stringValue { return s }
            if let v = item.value as? String { return v }
            return nil
        }

        func firstData(_ items: [AVMetadataItem], _ commonKey: AVMetadataKey) -> Data? {
            guard let item = items.first(where: { $0.commonKey == commonKey }) else { return nil }
            if let d = item.dataValue { return d }
            if let v = item.value as? Data { return v }
            if let img = item.value as? UIImage, let d = img.pngData() { return d }
            return nil
        }

        let common = asset.commonMetadata
        out.title = firstString(common, .commonKeyTitle)
        out.artist = firstString(common, .commonKeyArtist)
        out.album = firstString(common, .commonKeyAlbumName)
        out.artworkData = firstData(common, .commonKeyArtwork)

        if out.title == nil || out.artist == nil || out.album == nil || out.artworkData == nil {
            // Try ID3 / iTunes metadata formats
            for fmt in [AVMetadataFormat.id3Metadata, AVMetadataFormat.iTunesMetadata] {
                let items = asset.metadata(forFormat: fmt)
                if out.title == nil { out.title = firstString(items, .commonKeyTitle) }
                if out.artist == nil { out.artist = firstString(items, .commonKeyArtist) }
                if out.album == nil { out.album = firstString(items, .commonKeyAlbumName) }
                if out.artworkData == nil { out.artworkData = firstData(items, .commonKeyArtwork) }
            }
        }

        return out
    }

    private static func relativePath(of fileURL: URL, inside folderURL: URL) -> String {
        let folderPath = folderURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path

        if filePath.hasPrefix(folderPath) {
            var rel = String(filePath.dropFirst(folderPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            return rel
        }
        return fileURL.lastPathComponent
    }
}
