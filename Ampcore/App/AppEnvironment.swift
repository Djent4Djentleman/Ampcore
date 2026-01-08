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

    private var bag: Set<AnyCancellable> = []

    private init() {
        self.folderAccess = .shared
        self.settings = .shared
        self.player = .shared
        self.navigation = .init()

        player.managedObjectContext = PersistenceController.shared.container.viewContext

        // Forward player updates
        player.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)

        // Forward navigation updates
        navigation.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: AudioEnginePlayer.didFinishTrack)
            .sink { [weak self] _ in
                guard let self else { return }
                self.handleTrackEnded()
            }
            .store(in: &bag)
    }

    // MARK: - Library scan

    func scanLibrary(context: NSManagedObjectContext) throws -> MusicScanner.ScanResult {
        let bookmark = folderAccess.currentBookmarkData()
        return try folderAccess.withResolvedAccess { folderURL in
            try MusicScanner.scanAndUpsert(
                folderURL: folderURL,
                folderBookmark: bookmark,
                context: context
            )
        }
    }

    func autoScanIfNeeded(context: NSManagedObjectContext) {
        guard settings.autoScanOnLaunch else { return }
        guard folderAccess.currentBookmarkData() != nil else { return }

        do {
            _ = try scanLibrary(context: context)
        } catch {
            // Ignore
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
