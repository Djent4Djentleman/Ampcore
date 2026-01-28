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
        var genre: String?
        /// Release year (0 = unknown)
        var year: Int?
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
            out.genre = await firstStringValue(commonKeyRaw: "genre", in: items)

            if let artItem = items.first(where: { $0.commonKey == .commonKeyArtwork }) {
                out.artworkData = await dataValue(of: artItem)
            }
        } catch { }

        // Year is not reliably exposed via commonKey — check all metadata formats.
        do {
            let all = try await asset.load(.metadata)

            if let year = await firstYear(in: all) {
                out.year = year
            } else if let creation = await firstStringValue(for: .commonKeyCreationDate, in: all) {
                out.year = parseYear(from: creation)
            }
        } catch { }

        return out
    }

    // MARK: - Helpers

    private static func firstStringValue(for key: AVMetadataKey, in items: [AVMetadataItem]) async -> String? {
        guard let item = items.first(where: { $0.commonKey == key }) else { return nil }
        return await stringValue(of: item)
    }

    private static func firstStringValue(commonKeyRaw raw: String, in items: [AVMetadataItem]) async -> String? {
        // Some common keys (like genre) are not represented as AVMetadataKey constants on all SDKs.
        guard let item = items.first(where: { $0.commonKey?.rawValue == raw }) else { return nil }
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

    private static func firstYear(in items: [AVMetadataItem]) async -> Int? {
        // Try common identifiers first (iTunes / QuickTime / ID3).
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
                if let s = await stringValue(of: item),
                   let y = parseYear(from: s) {
                    return y
                }
                // Some tags are numeric.
                do {
                    if let v = try await item.load(.value) {
                        if let n = v as? NSNumber {
                            let y = n.intValue
                            if y >= 1000, y <= 2999 { return y }
                        }
                        if let s = v as? String, let y = parseYear(from: s) { return y }
                    }
                } catch { }
            }
        }

        // As a last resort, scan any string metadata for a 4-digit year.
        for item in items {
            if let s = await stringValue(of: item), let y = parseYear(from: s) {
                return y
            }
        }

        return nil
    }

    private static func parseYear(from value: String) -> Int? {
        // Accept formats like "2020", "2020-05-01", "2020/05/01", "2020-00-00", etc.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Find the first 4-digit year between 1000 and 2999.
        let pattern = #"(?<!\d)(1\d{3}|2\d{3})(?!\d)"#
        if let r = trimmed.range(of: pattern, options: .regularExpression) {
            let y = Int(trimmed[r]) ?? 0
            if y >= 1000, y <= 2999 { return y }
        }
        return nil
    }
}
