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
                    track.isFavorite = false
                    track.rating = 0
                    track.playCount = 0
                    track.lastPlayedAt = nil
                    track.year = 0

                    added += 1
                } else {
                    updated += 1
                }
                
                let titleTrimmed = meta.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let titleClean = (titleTrimmed?.isEmpty == false) ? titleTrimmed : nil
                
                track.title = titleClean ?? baseName

                let artistTrimmed = meta.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                track.artist = artistTrimmed.isEmpty ? nil : artistTrimmed

                let albumTrimmed = meta.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                track.album = albumTrimmed.isEmpty ? nil : albumTrimmed

                let genreTrimmed = meta.genre?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                track.genre = genreTrimmed.isEmpty ? nil : genreTrimmed

                if let y = meta.year, y >= 1000, y <= 2999 {
                    track.year = Int16(y)
                } else {
                    track.year = 0
                }

                
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
        var genre: String?
        /// Release year (0 = unknown)
        var year: Int?
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
            out.genre = await firstStringCommonRaw(common, "genre")
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
        

        // Year is not reliably exposed via commonKey — check all metadata formats (best-effort).
        do {
            let all = try await asset.load(.metadata)
            if let y = await firstYear(in: all) {
                out.year = y
            } else if let creation = await firstString(all, .commonKeyCreationDate) {
                out.year = parseYear(from: creation)
            }
        } catch { }

        return out
    }
    
    private static func firstString(_ items: [AVMetadataItem], _ commonKey: AVMetadataKey) async -> String? {
        guard let item = items.first(where: { $0.commonKey == commonKey }) else { return nil }
        
        if let s = try? await item.load(.stringValue) { return s }
        if let v = try? await item.load(.value) as? String { return v }
        return nil
    }
    
    
    private static func firstStringCommonRaw(_ items: [AVMetadataItem], _ raw: String) async -> String? {
        guard let item = items.first(where: { $0.commonKey?.rawValue == raw }) else { return nil }
        if let s = try? await item.load(.stringValue) { return s }
        if let v = try? await item.load(.value) {
            if let s = v as? String { return s }
            return String(describing: v)
        }
        return nil
    }

    private static func firstYear(in items: [AVMetadataItem]) async -> Int? {
        let identifiers: [AVMetadataIdentifier] = [
            .iTunesMetadataReleaseDate,
            .quickTimeMetadataYear,
            .quickTimeMetadataCreationDate,
            .id3MetadataYear,
            .id3MetadataRecordingTime,
            .id3MetadataDate
        ]

        for id in identifiers {
            if let item = items.first(where: { $0.identifier == id }) {
                if let s = try? await item.load(.stringValue), let y = parseYear(from: s) { return y }
                if let v = try? await item.load(.value) {
                    if let n = v as? NSNumber {
                        let y = n.intValue
                        if y >= 1000, y <= 2999 { return y }
                    }
                    if let s = v as? String, let y = parseYear(from: s) { return y }
                }
            }
        }

        // Last resort: scan strings for a 4-digit year.
        for item in items {
            if let s = try? await item.load(.stringValue), let y = parseYear(from: s) { return y }
        }
        return nil
    }

    private static func parseYear(from value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pattern = #"(?<!\d)(1\d{3}|2\d{3})(?!\d)"#
        if let r = trimmed.range(of: pattern, options: .regularExpression) {
            let y = Int(trimmed[r]) ?? 0
            if y >= 1000, y <= 2999 { return y }
        }
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
