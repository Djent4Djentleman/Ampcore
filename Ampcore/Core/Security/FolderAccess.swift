import Foundation

enum FolderAccessError: Error { case denied, stale }

enum FolderAccess {
    static func startAccessing(bookmark: Data) throws -> URL {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark,
                          options: [.withSecurityScope],
                          bookmarkDataIsStale: &isStale)
        guard url.startAccessingSecurityScopedResource() else { throw FolderAccessError.denied }
        if isStale { throw FolderAccessError.stale }
        return url
    }
    
    static func stopAccessing(url: URL) { url.stopAccessingSecurityScopedResource() }
    
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope],
                             includingResourceValuesForKeys: nil,
                             relativeTo: nil)
    }
}
