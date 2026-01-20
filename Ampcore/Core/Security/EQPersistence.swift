import Foundation
import Combine

// MARK: - Models

struct EQSnapshot: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case eqEnabled, toneEnabled, limiterEnabled, limiterAmount
        case bandValues, bass, treble, selectedPresetId
    }
    
    init(
        eqEnabled: Bool,
        toneEnabled: Bool,
        limiterEnabled: Bool,
        limiterAmount: Double,
        bandValues: [Double],
        bass: Double,
        treble: Double,
        selectedPresetId: String
    ) {
        self.eqEnabled = eqEnabled
        self.toneEnabled = toneEnabled
        self.limiterEnabled = limiterEnabled
        self.limiterAmount = limiterAmount
        self.bandValues = bandValues
        self.bass = bass
        self.treble = treble
        self.selectedPresetId = selectedPresetId
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.eqEnabled = try c.decode(Bool.self, forKey: .eqEnabled)
        self.toneEnabled = try c.decode(Bool.self, forKey: .toneEnabled)
        self.limiterEnabled = try c.decode(Bool.self, forKey: .limiterEnabled)
        self.limiterAmount = try c.decodeIfPresent(Double.self, forKey: .limiterAmount) ?? 0
        self.bandValues = try c.decode([Double].self, forKey: .bandValues)
        self.bass = try c.decode(Double.self, forKey: .bass)
        self.treble = try c.decode(Double.self, forKey: .treble)
        self.selectedPresetId = try c.decode(String.self, forKey: .selectedPresetId)
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(eqEnabled, forKey: .eqEnabled)
        try c.encode(toneEnabled, forKey: .toneEnabled)
        try c.encode(limiterEnabled, forKey: .limiterEnabled)
        try c.encode(limiterAmount, forKey: .limiterAmount)
        try c.encode(bandValues, forKey: .bandValues)
        try c.encode(bass, forKey: .bass)
        try c.encode(treble, forKey: .treble)
        try c.encode(selectedPresetId, forKey: .selectedPresetId)
    }
    var eqEnabled: Bool
    var toneEnabled: Bool
    var limiterEnabled: Bool
    
    /// 0...100 (Pro Limiter amount)
    var limiterAmount: Double
    
    /// 10 values: [Pre, 31, 62, 125, 250, 500, 1K, 2K, 4K, 8K]
    var bandValues: [Double]
    
    /// 0...100
    var bass: Double
    var treble: Double
    
    /// Built-in preset ids are "builtin:<rawValue>", user preset ids are UUID strings
    var selectedPresetId: String
    
    static func `default`() -> EQSnapshot {
        EQSnapshot(
            eqEnabled: false,
            toneEnabled: false,
            limiterEnabled: false,
            limiterAmount: 0,
            bandValues: Array(repeating: 0, count: 10),
            bass: 0,
            treble: 0,
            selectedPresetId: BuiltInEQPreset.flat.id
        )
    }
    
    func normalized10() -> EQSnapshot {
        var s = self
        if s.bandValues.count > 10 { s.bandValues = Array(s.bandValues.prefix(10)) }
        if s.bandValues.count < 10 { s.bandValues += Array(repeating: 0, count: 10 - s.bandValues.count) }
        // Clamp legacy persisted tone values (older builds allowed negative values).
        s.bass = min(max(s.bass, 0), 100)
        s.treble = min(max(s.treble, 0), 100)
        s.limiterAmount = min(max(s.limiterAmount, 0), 100)
        return s
    }
}

struct UserEQPreset: Codable, Equatable, Identifiable {
    var id: String            // UUID string
    var name: String
    var bandValues: [Double]  // 10 values
    var bass: Double
    var treble: Double
}

// MARK: - Built-ins

enum BuiltInEQPreset: String, CaseIterable, Identifiable {
    case flat, rock, bassBoost, trebleBoost, vShape, vocal, metal, dance, acoustic
    
    var id: String { "builtin:\(rawValue)" }
    
    var title: String {
        switch self {
        case .flat: return "Flat"
        case .rock: return "Rock"
        case .bassBoost: return "Bass Boost"
        case .trebleBoost: return "Treble Boost"
        case .vShape: return "V-Shape"
        case .vocal: return "Vocal"
        case .metal: return "Metal"
        case .dance: return "Dance"
        case .acoustic: return "Acoustic"
        }
    }
    
    /// 10 values: Pre + 9 bands
    var bandValues: [Double] {
        switch self {
        case .flat:        return [0, 0,0,0,0,0,0,0,0,0]
        case .rock:        return [0, 3,2,1,0.5,-0.5,1.5,3,1,0.5]
        case .bassBoost:   return [2, 6,5,3,1,0,-1,-1,-1,-1]
        case .trebleBoost: return [0, -1,-1,0,1,2,4,5,6,5]
        case .vShape:      return [0, 4,3,1,-1,-1,1,3,4,3]
        case .vocal:       return [0, -2,-1,1,3,3,2,1,0,0]
        case .metal:       return [0, 4,3,0,-1,1,3,4,2,1]
        case .dance:       return [0, 5,4,2,0,-1,1,3,4,3]
        case .acoustic:    return [0, -1,0,1,2,2,1,0,-1,-1]
        }
    }
}

// MARK: - Store

@MainActor
final class EQStore: ObservableObject {
    @Published var snapshot: EQSnapshot
    @Published var userPresets: [UserEQPreset]
    
    private let snapshotKey = "ampcore.eq.snapshot.v1"
    private let userPresetsKey = "ampcore.eq.userpresets.v1"
    
    private var cancellables = Set<AnyCancellable>()
    private let defaults: UserDefaults
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.snapshot = EQStore.load(EQSnapshot.self, key: snapshotKey, defaults: defaults)?.normalized10() ?? .default()
        self.userPresets = EQStore.load([UserEQPreset].self, key: userPresetsKey, defaults: defaults) ?? []
        
        // Auto-save anytime changed
        $snapshot
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                self?.save(value.normalized10(), key: self?.snapshotKey ?? "")
            }
            .store(in: &cancellables)
        
        $userPresets
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                self?.save(value, key: self?.userPresetsKey ?? "")
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Presets
    
    func selectBuiltIn(_ p: BuiltInEQPreset, keepEQEnabled: Bool = true) {
        snapshot.selectedPresetId = p.id
        snapshot.bandValues = p.bandValues
        if keepEQEnabled { snapshot.eqEnabled = true }
    }
    
    func selectUserPreset(id: String, keepEQEnabled: Bool = true) {
        guard let p = userPresets.first(where: { $0.id == id }) else { return }
        snapshot.selectedPresetId = p.id
        snapshot.bandValues = normalized10(p.bandValues)
        snapshot.bass = p.bass
        snapshot.treble = p.treble
        if keepEQEnabled { snapshot.eqEnabled = true }
    }
    
    func saveCurrentAsUserPreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let id = UUID().uuidString
        let preset = UserEQPreset(
            id: id,
            name: trimmed,
            bandValues: normalized10(snapshot.bandValues),
            bass: snapshot.bass,
            treble: snapshot.treble
        )
        userPresets.insert(preset, at: 0)
        snapshot.selectedPresetId = id
    }
    
    func deleteUserPreset(id: String) {
        userPresets.removeAll { $0.id == id }
        if snapshot.selectedPresetId == id {
            snapshot.selectedPresetId = BuiltInEQPreset.flat.id
        }
    }
    
    // MARK: - Helpers
    
    func normalized10(_ v: [Double]) -> [Double] {
        if v.count == 10 { return v }
        if v.count > 10 { return Array(v.prefix(10)) }
        return v + Array(repeating: 0, count: max(0, 10 - v.count))
    }
    
    private func save<T: Encodable>(_ value: T, key: String) {
        guard !key.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(value)
            defaults.set(data, forKey: key)
        } catch {
            // no-op
        }
    }
    
    private static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
