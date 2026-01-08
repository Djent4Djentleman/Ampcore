import Foundation
import CoreData

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
                
                let req = CDTrack.fetchRequest()
                guard let typedReq = req as? NSFetchRequest<CDTrack> else { continue }
                typedReq.fetchLimit = 1
                typedReq.predicate = NSPredicate(format: "relativePath == %@", rel)
                
                let existing = try context.fetch(typedReq).first
                let track = existing ?? CDTrack(context: context)
                
                if existing == nil {
                    track.id = UUID()
                    track.addedAt = Date()
                    added += 1
                } else {
                    updated += 1
                }
                
                let baseName = url.deletingPathExtension().lastPathComponent
                track.title = baseName
                
                if track.artist == nil { track.artist = "" }
                if track.album == nil { track.album = "" }
                
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
