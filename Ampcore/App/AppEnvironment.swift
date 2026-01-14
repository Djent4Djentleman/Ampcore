import Foundation
import Combine
import CoreData

@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()
    
    @Published var folderAccess: FolderAccess
    @Published var settings: AppSettings
    @Published var player: AudioEnginePlayer
    @Published var navigation: AppNavigation
    @Published var eqStore: EQStore
    
    private var bag: Set<AnyCancellable> = []
    
    private init() {
        self.folderAccess = .shared
        self.settings = .shared
        self.player = .shared
        self.navigation = .init()
        self.eqStore = .init()
        
        player.managedObjectContext = PersistenceController.shared.container.viewContext
        
        // Forward player updates
        player.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        
        // Forward eqStore updates
        eqStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        
        // Apply settings to player
        player.applySettings(settings)
        
        settings.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.player.applySettings(self.settings)
                self.objectWillChange.send()
            }
            .store(in: &bag)
        
        // Forward navigation updates
        navigation.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        
        NotificationCenter.default.publisher(for: AudioEnginePlayer.didFinishTrack)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.handleTrackEnded()
            }
            .store(in: &bag)
    }
    
    // MARK: - Library scan
    
    func scanLibrary(context: NSManagedObjectContext) async throws -> MusicScanner.ScanResult {
        guard let bookmark = folderAccess.currentBookmarkData() else {
            throw FolderAccessError.bookmarkMissing
        }
        
        let folderURL = try folderAccess.resolveFolderURL()
        let ok = folderURL.startAccessingSecurityScopedResource()
        if !ok { throw FolderAccessError.securityScopeDenied }
        defer { folderURL.stopAccessingSecurityScopedResource() }
        
        return try await MusicScanner.scanAndUpsert(
            folderURL: folderURL,
            folderBookmark: bookmark,
            context: context
        )
    }
    
    func autoScanIfNeeded(context: NSManagedObjectContext) {
        guard settings.autoScanOnLaunch else { return }
        guard folderAccess.currentBookmarkData() != nil else { return }
        
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            
            do {
                _ = try await self.scanLibrary(context: context)
            } catch {
                // Ignore
            }
        }
    }
    
    // MARK: - Playback helpers
    
    func playFromLibrary(_ track: CDTrack, allTracks: [CDTrack]) {
        let ids = allTracks.map { $0.objectID }
        player.setQueue(ids: ids, startAt: track.objectID)
        player.play(track: track)
        navigation.showPlayer()
    }
    
    func togglePlayPause(context: NSManagedObjectContext) {
        if player.isPlaying {
            player.pause()
            return
        }
        
        if player.hasLoadedFile {
            player.resume()
            return
        }
        
        if let id = player.currentTrackID,
           let t = try? context.existingObject(with: id) as? CDTrack {
            player.play(track: t)
        }
    }
    
    func playNext(context: NSManagedObjectContext) {
        guard let id = player.nextTrackID() else { return }
        if let t = try? context.existingObject(with: id) as? CDTrack {
            player.play(track: t)
        }
    }
    
    func playPrev(context: NSManagedObjectContext) {
        // Restart
        if player.currentTime > 2.0 {
            player.seekUI(to: 0)
            return
        }
        
        guard let id = player.prevTrackID() else { return }
        if let t = try? context.existingObject(with: id) as? CDTrack {
            player.play(track: t)
        }
    }
    
    private func handleTrackEnded() {
        // Requires viewContext
        let moc = PersistenceController.shared.container.viewContext
        
        switch player.repeatMode {
        case .one:
            player.seekUI(to: 0)
            player.resume()
            
        case .all, .off:
            if let id = player.nextTrackID(whenEnded: true) {
                if let t = try? moc.existingObject(with: id) as? CDTrack {
                    player.play(track: t)
                }
            }
        }
    }
}
