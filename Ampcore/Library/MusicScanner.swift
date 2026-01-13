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
        let lock = NSLock()
        let semaphore = DispatchSemaphore(value: 0)
        var result = SyncMeta()
        
        Task {
            var out = SyncMeta()
            do {
                let duration = try await asset.load(.duration)
                let durSeconds = CMTimeGetSeconds(duration)
                if durSeconds.isFinite, durSeconds > 0 { out.duration = durSeconds }
                
                let common = try await asset.load(.commonMetadata)
                out.title = await firstString(common, .commonKeyTitle)
                out.artist = await firstString(common, .commonKeyArtist)
                out.album = await firstString(common, .commonKeyAlbumName)
                out.artworkData = await firstData(common, .commonKeyArtwork)
                
                if out.title == nil || out.artist == nil || out.album == nil || out.artworkData == nil {
                    // Try ID3 / iTunes metadata formats
                    for fmt in [AVMetadataFormat.id3Metadata, AVMetadataFormat.iTunesMetadata] {
                        let items = try await asset.loadMetadata(for: fmt)
                        if out.title == nil { out.title = await firstString(items, .commonKeyTitle) }
                        if out.artist == nil { out.artist = await firstString(items, .commonKeyArtist) }
                        if out.album == nil { out.album = await firstString(items, .commonKeyAlbumName) }
                        if out.artworkData == nil { out.artworkData = await firstData(items, .commonKeyArtwork) }
                    }
                }
            } catch {
                // Ignore metadata load failures; return partial data.
            }
            lock.lock()
            result = out
            lock.unlock()
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }
    
    private static func firstString(_ items: [AVMetadataItem], _ commonKey: AVMetadataKey) async -> String? {
        guard let item = items.first(where: { $0.commonKey == commonKey }) else { return nil }
        if let s = try? await item.load(.stringValue), let s { return s }
        if let v = try? await item.load(.value) as? String { return v }
        return nil
    }
    
    private static func firstData(_ items: [AVMetadataItem], _ commonKey: AVMetadataKey) async -> Data? {
        guard let item = items.first(where: { $0.commonKey == commonKey }) else { return nil }
        if let d = try? await item.load(.dataValue), let d { return d }
        if let v = try? await item.load(.value) as? Data { return v }
        if let v = try? await item.load(.value), let img = v as? UIImage, let d = img.pngData() { return d }
        return nil
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
