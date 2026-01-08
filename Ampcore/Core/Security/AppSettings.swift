import Foundation
import SwiftUI
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    
    // Library
    @AppStorage("settings.autoScanOnLaunch") var autoScanOnLaunch: Bool = false
    
    // Audio
    @AppStorage("settings.crossfadeEnabled") var crossfadeEnabled: Bool = false
    @AppStorage("settings.crossfadeSeconds") var crossfadeSeconds: Double = 6
    @AppStorage("settings.fadeInEnabled") var fadeInEnabled: Bool = false
    @AppStorage("settings.fadeInSeconds") var fadeInSeconds: Double = 0.3
    @AppStorage("settings.gaplessEnabled") var gaplessEnabled: Bool = true
    @AppStorage("settings.replayGainEnabled") var replayGainEnabled: Bool = false
    
    // Album Art
    @AppStorage("settings.artworkQualityHD") var artworkQualityHD: Bool = true
    @AppStorage("settings.artworkWifiOnly") var artworkWifiOnly: Bool = true
    
    
    // Look & Feel
    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }
    
    @AppStorage("settings.theme") private var themeRaw: String = Theme.system.rawValue
    var theme: Theme {
        get { Theme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue }
    }
    
    enum FontChoice: String, CaseIterable, Identifiable {
        case baaqua, system
        var id: String { rawValue }
        var title: String { self == .baaqua ? "BaAQUA" : "System (SF)" }
    }
    
    @AppStorage("settings.fontChoice") private var fontChoiceRaw: String = FontChoice.baaqua.rawValue
    var fontChoice: FontChoice {
        get { FontChoice(rawValue: fontChoiceRaw) ?? .baaqua }
        set { fontChoiceRaw = newValue.rawValue }
    }
    
    @AppStorage("settings.boldText") var boldText: Bool = false
    
    private init() {}
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
    
    /// Набор полос (как на скрине, можно расширить позже)
    static let eqBands: [EQBand] = [31, 62, 125, 250, 500, 1000, 2000, 4000].map { EQBand($0) }
    
    /// Вкл/выкл EQ
    @Published var eqEnabled: Bool = true
    
    /// Значения каждой полосы в dB (например -12...+12)
    @Published var eqGainsDB: [Double] = Array(repeating: 0.0, count: AppSettings.eqBands.count)
    
    /// Preamp в dB (-12...+12)
    @Published var eqPreampDB: Double = 0.0
    
    // тут могут быть твои другие настройки (папка, шрифт, wifi-only и т.д.)
}
