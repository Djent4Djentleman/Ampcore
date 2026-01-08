import Foundation

enum Formatters {
    static func time(_ s: TimeInterval) -> String {
        guard s.isFinite else { return "0:00" }
        let sec = Int(s.rounded(.down))
        let m = sec / 60
        let r = sec % 60
        return "\(m):" + String(format: "%02d", r)
    }
}
