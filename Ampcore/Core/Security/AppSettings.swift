import Foundation
import SwiftUI
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    private enum Keys {
        static let autoScanOnLaunch = "settings.autoScanOnLaunch"
        static let crossfadeEnabled = "settings.crossfadeEnabled"
        static let crossfadeSeconds = "settings.crossfadeSeconds"
        static let fadeTransportEnabled = "settings.fadeTransportEnabled"
        static let fadeTransportSeconds = "settings.fadeTransportSeconds"
        static let fadeSeekEnabled = "settings.fadeSeekEnabled"
        static let fadeSeekSeconds = "settings.fadeSeekSeconds"
        static let gaplessEnabled = "settings.gaplessEnabled"
        static let replayGainEnabled = "settings.replayGainEnabled"
        static let artworkQualityHD = "settings.artworkQualityHD"
        static let artworkWifiOnly = "settings.artworkWifiOnly"
        static let theme = "settings.theme"
        static let fontChoice = "settings.fontChoice"
        static let boldText = "settings.boldText"
    }
    
    private let defaults: UserDefaults
    
    // Library
    @Published var autoScanOnLaunch: Bool = false {
        didSet { defaults.set(autoScanOnLaunch, forKey: Keys.autoScanOnLaunch) }
    }
    
    // Audio
    @Published var crossfadeEnabled: Bool = false {
        didSet { defaults.set(crossfadeEnabled, forKey: Keys.crossfadeEnabled) }
    }
    @Published var crossfadeSeconds: Double = 6 {
        didSet { defaults.set(crossfadeSeconds, forKey: Keys.crossfadeSeconds) }
    }
    @Published var fadeTransportEnabled: Bool = false {
        didSet { defaults.set(fadeTransportEnabled, forKey: Keys.fadeTransportEnabled) }
    }
    @Published var fadeTransportSeconds: Double = 0.30 {
        didSet { defaults.set(fadeTransportSeconds, forKey: Keys.fadeTransportSeconds) }
    }
    @Published var fadeSeekEnabled: Bool = false {
        didSet { defaults.set(fadeSeekEnabled, forKey: Keys.fadeSeekEnabled) }
    }
    @Published var fadeSeekSeconds: Double = 0.08 {
        didSet { defaults.set(fadeSeekSeconds, forKey: Keys.fadeSeekSeconds) }
    }
    
    @Published var gaplessEnabled: Bool = true {
        didSet { defaults.set(gaplessEnabled, forKey: Keys.gaplessEnabled) }
    }
    @Published var replayGainEnabled: Bool = false {
        didSet { defaults.set(replayGainEnabled, forKey: Keys.replayGainEnabled) }
    }
    
    // Album Art
    @Published var artworkQualityHD: Bool = true {
        didSet { defaults.set(artworkQualityHD, forKey: Keys.artworkQualityHD) }
    }
    @Published var artworkWifiOnly: Bool = true {
        didSet { defaults.set(artworkWifiOnly, forKey: Keys.artworkWifiOnly) }
    }
    
    // Look & Feel
    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }
    
    @Published private var themeRaw: String = Theme.system.rawValue {
        didSet { defaults.set(themeRaw, forKey: Keys.theme) }
    }
    var theme: Theme {
        get { Theme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue }
    }
    
    enum FontChoice: String, CaseIterable, Identifiable {
        case baaqua, system
        var id: String { rawValue }
        var title: String { self == .baaqua ? "BaAQUA" : "System (SF)" }
    }
    
    @Published private var fontChoiceRaw: String = FontChoice.baaqua.rawValue {
        didSet { defaults.set(fontChoiceRaw, forKey: Keys.fontChoice) }
    }
    var fontChoice: FontChoice {
        get { FontChoice(rawValue: fontChoiceRaw) ?? .baaqua }
        set { fontChoiceRaw = newValue.rawValue }
    }
    
    @Published var boldText: Bool = false {
        didSet { defaults.set(boldText, forKey: Keys.boldText) }
    }
    
    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        if defaults.object(forKey: Keys.autoScanOnLaunch) != nil {
            autoScanOnLaunch = defaults.bool(forKey: Keys.autoScanOnLaunch)
        }
        
        if defaults.object(forKey: Keys.crossfadeEnabled) != nil {
            crossfadeEnabled = defaults.bool(forKey: Keys.crossfadeEnabled)
        }
        if defaults.object(forKey: Keys.crossfadeSeconds) != nil {
            crossfadeSeconds = defaults.double(forKey: Keys.crossfadeSeconds)
        }
        if defaults.object(forKey: Keys.fadeTransportEnabled) != nil {
            fadeTransportEnabled = defaults.bool(forKey: Keys.fadeTransportEnabled)
        }
        if defaults.object(forKey: Keys.fadeTransportSeconds) != nil {
            fadeTransportSeconds = defaults.double(forKey: Keys.fadeTransportSeconds)
        }
        if defaults.object(forKey: Keys.fadeSeekEnabled) != nil {
            fadeSeekEnabled = defaults.bool(forKey: Keys.fadeSeekEnabled)
        }
        if defaults.object(forKey: Keys.fadeSeekSeconds) != nil {
            fadeSeekSeconds = defaults.double(forKey: Keys.fadeSeekSeconds)
        }
        if defaults.object(forKey: Keys.gaplessEnabled) != nil {
            gaplessEnabled = defaults.bool(forKey: Keys.gaplessEnabled)
        }
        if defaults.object(forKey: Keys.replayGainEnabled) != nil {
            replayGainEnabled = defaults.bool(forKey: Keys.replayGainEnabled)
        }
        
        if defaults.object(forKey: Keys.artworkQualityHD) != nil {
            artworkQualityHD = defaults.bool(forKey: Keys.artworkQualityHD)
        }
        if defaults.object(forKey: Keys.artworkWifiOnly) != nil {
            artworkWifiOnly = defaults.bool(forKey: Keys.artworkWifiOnly)
        }
        
        if let themeValue = defaults.string(forKey: Keys.theme) {
            themeRaw = themeValue
        }
        if let fontValue = defaults.string(forKey: Keys.fontChoice) {
            fontChoiceRaw = fontValue
        }
        if defaults.object(forKey: Keys.boldText) != nil {
            boldText = defaults.bool(forKey: Keys.boldText)
        }
    }
    
    // MARK: - EQ
    
    struct EQBand: Identifiable, Hashable {
        let id = UUID()
        let hz: Int
        let label: String
        
        init(_ hz: Int) {
            self.hz = hz
            self.label = hz >= 1000 ? "\(hz / 1000)K" : "\(hz)"
        }
    }
    
    /// EQ band list used by the UI.
    static let eqBands: [EQBand] = [31, 62, 125, 250, 500, 1000, 2000, 4000].map { EQBand($0) }
    
    /// EQ on/off state.
    @Published var eqEnabled: Bool = true
    
    /// Band gains in dB (-12...+12).
    @Published var eqGainsDB: [Double] = Array(repeating: 0.0, count: AppSettings.eqBands.count)
    
    /// Preamp in dB (-12...+12).
    @Published var eqPreampDB: Double = 0.0
}
