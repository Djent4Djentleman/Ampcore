import Foundation
import CoreData
import AVFoundation
import UIKit

// MARK: - MusicScanner

enum MusicScanner {
    struct ScanResult {
        let added: Int
        let updated: Int
    }
    
    // Supported extensions
    private static let supportedExts: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac"
    ]
    
    // Serialize scans to avoid concurrent upserts.
    private actor ScanGate {
        private var isRunning = false
        
        func enter() async {
            while isRunning {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
            isRunning = true
        }
        
        func leave() {
            isRunning = false
        }
    }
    
    private static let gate = ScanGate()
    
    // MARK: - Public API (preferred)
    
    static func scanAndUpsert(
        folderURL: URL,
        folderBookmark: Data?,
        context: NSManagedObjectContext
    ) async throws -> ScanResult {
        
        guard let folderBookmark else { throw FolderAccessError.bookmarkMissing }
        
        await gate.enter()
        defer { Task { await gate.leave() } }
        
        // Enumerate files (cheap, sync)
        let urls = enumerateAudioFiles(in: folderURL)
        
        var added = 0
        var updated = 0
        
        // Process sequentially for stability; can be parallelized later safely.
        // Save in batches to avoid huge transaction.
        let batchSize = 50
        var batchCount = 0
        
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let rel = relativePath(of: url, inside: folderURL)
            let baseName = url.deletingPathExtension().lastPathComponent
            
            let meta = await readMetadata(from: url)
            
            try await context.perform {
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
                
                let titleTrimmed = meta.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let titleClean = (titleTrimmed?.isEmpty == false) ? titleTrimmed : nil
                
                track.title = titleClean ?? baseName
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
            
            batchCount += 1
            if batchCount >= batchSize {
                batchCount = 0
                try await saveIfNeeded(context)
            }
        }
        
        try await saveIfNeeded(context)
        return ScanResult(added: added, updated: updated)
    }
    
    // MARK: - Backward compatible wrapper (sync)
    
    /// Backward-compatible sync wrapper.
    /// Prefer calling the async variant from a Task.
    static func scanAndUpsert(
        folderURL: URL,
        folderBookmark: Data?,
        context: NSManagedObjectContext
    ) throws -> ScanResult {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<ScanResult, Error> = .failure(NSError(domain: "MusicScanner", code: -1))
        
        Task(priority: .utility) {
            do {
                let r = try await scanAndUpsert(folderURL: folderURL, folderBookmark: folderBookmark, context: context)
                result = .success(r)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return try result.get()
    }
    
    // MARK: - Enumeration
    
    private static func enumerateAudioFiles(in folderURL: URL) -> [URL] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey, .nameKey]
        
        let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        )
        
        var urls: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            if !supportedExts.contains(ext) { continue }
            
            if let values = try? url.resourceValues(forKeys: Set(keys)) {
                if values.isHidden == true { continue }
                if values.isRegularFile != true { continue }
            }
            
            urls.append(url)
        }
        return urls
    }
    
    // MARK: - Metadata
    
    private struct Meta {
        var title: String?
        var artist: String?
        var album: String?
        var duration: Double?
        var artworkData: Data?
    }
    
    private static func readMetadata(from url: URL) async -> Meta {
        let asset = AVURLAsset(url: url)
        var out = Meta()
        
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
        
        return out
    }
    
    private static func firstString(_ items: [AVMetadataItem], _ commonKey: AVMetadataKey) async -> String? {
        guard let item = items.first(where: { $0.commonKey == commonKey }) else { return nil }
        
        if let s = try? await item.load(.stringValue) { return s }
        if let v = try? await item.load(.value) as? String { return v }
        return nil
    }
    
    private static func firstData(_ items: [AVMetadataItem], _ commonKey: AVMetadataKey) async -> Data? {
        guard let item = items.first(where: { $0.commonKey == commonKey }) else { return nil }
        
        if let d = try? await item.load(.dataValue) { return d }
        if let v = try? await item.load(.value) as? Data { return v }
        
        if let v = try? await item.load(.value) {
            // Some formats may return UIImage or other types.
            if let img = v as? UIImage { return img.pngData() }
        }
        
        return nil
    }
    
    // MARK: - CoreData
    
    private static func saveIfNeeded(_ context: NSManagedObjectContext) async throws {
        try await context.perform {
            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    // MARK: - Paths
    
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
