import Foundation

enum Selection {
    static func updating(excluded: Set<String>, id: String, enabled: Bool) -> Set<String> {
        var result = excluded
        if enabled { result.remove(id) } else { result.insert(id) }
        return result
    }
}
