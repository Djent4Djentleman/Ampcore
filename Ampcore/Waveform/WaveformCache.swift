import Foundation

actor WaveformCache {
    static let shared = WaveformCache()
    private let dir: URL
    
    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Waveforms", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    
    func load(id: UUID) -> [Float]? {
        let url = dir.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Float].self, from: data)
    }
    
    func save(_ peaks: [Float], id: UUID) {
        let url = dir.appendingPathComponent("\(id.uuidString).json")
        if let data = try? JSONEncoder().encode(peaks) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
