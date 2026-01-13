import Foundation
import AVFoundation
import UIKit

// MARK: - MetadataReader
// iOS 16+ async AVFoundation metadata loading.

enum MetadataReader {

    struct TrackMetadata: Sendable {
        var title: String?
        var artist: String?
        var album: String?
        var duration: TimeInterval?
        var artworkData: Data?
    }

    static func read(from url: URL) async -> TrackMetadata {
        let asset = AVURLAsset(url: url)
        var out = TrackMetadata()

        // Duration
        do {
            let time = try await asset.load(.duration)
            let secs = CMTimeGetSeconds(time)
            if secs.isFinite, secs > 0 { out.duration = secs }
        } catch { }

        // Common metadata
        do {
            let items = try await asset.load(.commonMetadata)

            out.title = await firstStringValue(for: .commonKeyTitle, in: items)
            out.artist = await firstStringValue(for: .commonKeyArtist, in: items)
            out.album = await firstStringValue(for: .commonKeyAlbumName, in: items)

            if let artItem = items.first(where: { $0.commonKey == .commonKeyArtwork }) {
                out.artworkData = await dataValue(of: artItem)
            }
        } catch { }

        return out
    }

    // MARK: - Helpers

    private static func firstStringValue(for key: AVMetadataKey, in items: [AVMetadataItem]) async -> String? {
        guard let item = items.first(where: { $0.commonKey == key }) else { return nil }
        return await stringValue(of: item)
    }

    private static func stringValue(of item: AVMetadataItem) async -> String? {
        do {
            return try await item.load(.stringValue)
        } catch {
            // Fallback (some sources still bridge value)
            do {
                if let v = try await item.load(.value) {
                    if let s = v as? String { return s }
                    return String(describing: v)
                }
            } catch { }
            return nil
        }
    }

    private static func dataValue(of item: AVMetadataItem) async -> Data? {
        do {
            return try await item.load(.dataValue)
        } catch {
            // Fallback (some sources still bridge value)
            do {
                if let v = try await item.load(.value) {
                    if let d = v as? Data { return d }
                }
            } catch { }
            return nil
        }
    }
}
