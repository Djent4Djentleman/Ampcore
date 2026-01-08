import Foundation

enum URLResolverError: Error {
    case securityScopeDenied
    case staleBookmark
}

enum URLResolver {
    static func resolveFolderURL(from bookmark: Data) throws -> URL {
        var stale = false
        
#if os(macOS)
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
#else
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
#endif
        
        if stale { throw URLResolverError.staleBookmark }
        return url
    }
    
    static func resolveFileURL(folderBookmark: Data, relativePath: String) throws -> URL {
        let folderURL = try resolveFolderURL(from: folderBookmark)
        return folderURL.appendingPathComponent(relativePath)
    }
    
    static func withSecurityScopedAccess<T>(_ url: URL, _ work: () throws -> T) throws -> T {
        guard url.startAccessingSecurityScopedResource() else {
            throw URLResolverError.securityScopeDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try work()
    }
}
