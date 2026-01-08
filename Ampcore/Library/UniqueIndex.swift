import Foundation

final class UniqueIndex {
    static let shared = UniqueIndex()
    private let key = "ampcore_unique_index"
    private var set: Set<String>
    
    private init() {
        if let arr = UserDefaults.standard.array(forKey: key) as? [String] {
            set = Set(arr)
        } else {
            set = []
        }
    }
    
    func contains(key: String) -> Bool { set.contains(key) }
    
    func markExisting(key: String) {
        set.insert(key)
        UserDefaults.standard.set(Array(set), forKey: self.key)
    }
}
