import Foundation
import Combine

enum FolderAccessError: LocalizedError {
    case noSelection
    case bookmarkMissing
    case bookmarkStale
    case securityScopeDenied
    case resolveFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .noSelection: return "No folder selected."
        case .bookmarkMissing: return "Folder bookmark is missing."
        case .bookmarkStale: return "Folder bookmark is stale."
        case .securityScopeDenied: return "Security-scoped access denied."
        case .resolveFailed(let e): return "Failed to resolve bookmark: \(e.localizedDescription)"
        }
    }
}

@MainActor
final class FolderAccess: ObservableObject {
    static let shared = FolderAccess()
    
    @Published private(set) var folderDisplayName: String? = nil
    
    private let bookmarkKey = "ampcore.musicFolderBookmark"
    
    private init() {
        // Restore display name
        _ = try? resolveFolderURL()
    }
    
    func currentBookmarkData() -> Data? {
        UserDefaults.standard.data(forKey: bookmarkKey)
    }
    
    func clearSelection() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        folderDisplayName = nil
    }
    
    // Store bookmark
    func storeSelectedFolder(url: URL) throws {
        let options: URL.BookmarkCreationOptions = {
#if os(macOS)
            return [.withSecurityScope]
#else
            // iOS: keep it compatible
            return [.minimalBookmark]
#endif
        }()
        
        let bookmark = try url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        folderDisplayName = url.lastPathComponent
    }
    
    // Resolve bookmark
    func resolveFolderURL() throws -> URL {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw FolderAccessError.bookmarkMissing
        }
        
        var stale = false
        do {
            let options: URL.BookmarkResolutionOptions = {
#if os(macOS)
                return [.withSecurityScope, .withoutUI]
#else
                return [.withoutUI]
#endif
            }()
            
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            
            if stale { throw FolderAccessError.bookmarkStale }
            
            folderDisplayName = url.lastPathComponent
            return url
        } catch {
            throw FolderAccessError.resolveFailed(error)
        }
    }
    
    // Security-scope helper
    func withAccess<T>(_ url: URL, _ work: () throws -> T) throws -> T {
        let ok = url.startAccessingSecurityScopedResource()
        if !ok { throw FolderAccessError.securityScopeDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        return try work()
    }
    
    // Convenience: resolve + access
    func withResolvedAccess<T>(_ work: (URL) throws -> T) throws -> T {
        let url = try resolveFolderURL()
        return try withAccess(url) { try work(url) }
    }
}
