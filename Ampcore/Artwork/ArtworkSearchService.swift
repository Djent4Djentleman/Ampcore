import Foundation

struct ArtworkCandidate: Identifiable {
    let id = UUID()
    let imageURL: URL
    let sourceTitle: String
}

final class ArtworkSearchService {
    func search(artist: String?, album: String?, title: String?) async throws -> [ArtworkCandidate] {
        let termParts = [artist, album].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let term = termParts.isEmpty ? (title ?? "") : termParts.joined(separator: " ")
        let q = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(q)&entity=album&limit=25") else { return [] }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = json?["results"] as? [[String: Any]] ?? []
        
        return results.compactMap { item in
            guard let artwork = item["artworkUrl100"] as? String,
                  let hi = URL(string: artwork.replacingOccurrences(of: "100x100bb", with: "600x600bb")) else { return nil }
            let name = (item["collectionName"] as? String) ?? "iTunes"
            return ArtworkCandidate(imageURL: hi, sourceTitle: name)
        }
    }
}
