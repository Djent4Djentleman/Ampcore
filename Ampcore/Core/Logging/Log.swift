import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Ampcore"
    
    static let app = Logger(subsystem: subsystem, category: "app")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let library = Logger(subsystem: subsystem, category: "library")
    static let meta = Logger(subsystem: subsystem, category: "meta")          // ✅ добавили
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
